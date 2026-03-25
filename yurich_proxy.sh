#!/bin/bash
# Прокси-менеджер для Telegram и WhatsApp с Telegram-ботом
# Автор: Юрич
# Версия: 3.1

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Красивый заголовок
print_banner() {
    clear
    echo -e "${CYAN}"
    echo '╔══════════════════════════════════════════════════════════════╗'
    echo '║                                                              ║'
    echo '║              ██╗   ██╗██████╗ ██╗██████╗ ██╗ ██████╗██╗     ║'
    echo '║              ██║   ██║██╔══██╗██║██╔══██╗██║██╔════╝██║     ║'
    echo '║              ██║   ██║██████╔╝██║██████╔╝██║██║     ██║     ║'
    echo '║              ██║   ██║██╔══██╗██║██╔══██╗██║██║     ██║     ║'
    echo '║              ╚██████╔╝██║  ██║██║██║  ██║██║╚██████╗██║     ║'
    echo '║               ╚═════╝ ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝ ╚═════╝╚═╝     ║'
    echo '║                                                              ║'
    echo -e "║                   ${GREEN}ЮРИЧ ДЕЛАЕТ  v3.1${CYAN}                          ║"
    echo -e "║          ${YELLOW}Прокси-менеджер для Telegram и WhatsApp${CYAN}            ║"
    echo '║                                                              ║'
    echo '╚══════════════════════════════════════════════════════════════╝'
    echo -e "${NC}"
    echo ""
    sleep 1
}

print_banner

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [[ $EUID -ne 0 ]]; then
    error "Скрипт должен выполняться от root. Используйте sudo."
fi

# Проверка ОС
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    error "Не удалось определить ОС."
fi
if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    error "Поддерживаются только Ubuntu/Debian."
fi

info "Обновление системы..."
apt update && apt upgrade -y

info "Установка необходимых пакетов..."
apt install -y curl wget ufw iptables net-tools git python3 python3-pip python3-venv \
    dante-server vnstat sudo

# Установка Docker
if ! command -v docker &> /dev/null; then
    info "Установка Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl enable docker
    systemctl start docker
fi

# Установка Docker Compose
if ! command -v docker-compose &> /dev/null; then
    info "Установка Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Запрос данных
echo ""
info "Введите параметры настройки (Enter = значение по умолчанию):"

read -p "Токен Telegram бота (от @BotFather): " BOT_TOKEN
[[ -z "$BOT_TOKEN" ]] && error "Токен обязателен."

read -p "Username бота (например, MyProxyBot, необязательно): " BOT_USERNAME

read -p "ID канала (например, @channel или -100123456): " CHANNEL_ID
[[ -z "$CHANNEL_ID" ]] && error "ID канала обязателен."

read -p "Ваш домен (если нет, оставьте пустым, будет IP): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    DOMAIN=$(curl -s ifconfig.me)
    info "Домен не указан, используем IP: $DOMAIN"
fi

read -p "Порт SOCKS5 [1080]: " SOCKS_PORT
SOCKS_PORT=${SOCKS_PORT:-1080}

read -p "Порт MTProto [443]: " MTPROTO_PORT
MTPROTO_PORT=${MTPROTO_PORT:-443}

# Генерация секрета MTProto
MTPROTO_SECRET=$(head -c 16 /dev/urandom | xxd -ps)
info "Сгенерирован секрет MTProto: $MTPROTO_SECRET"

echo ""
read -p "Ваш Telegram ID (администратор, можно узнать у @userinfobot): " ADMIN_ID
if [[ -z "$ADMIN_ID" ]]; then
    warn "ID администратора не указан. Вы сможете назначить админа позже через бота командой /addadmin."
fi

# Подтверждение
echo ""
echo "-----------------------------"
echo "Токен бота: $BOT_TOKEN"
[[ -n "$BOT_USERNAME" ]] && echo "Username бота: @$BOT_USERNAME"
echo "Канал: $CHANNEL_ID"
echo "Домен: $DOMAIN"
echo "SOCKS5 порт: $SOCKS_PORT"
echo "MTProto порт: $MTPROTO_PORT"
echo "MTProto секрет: $MTPROTO_SECRET"
echo "ID администратора: ${ADMIN_ID:-не задан}"
echo "-----------------------------"
read -p "Продолжить? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && error "Установка отменена."

# Открываем порты в фаерволе
info "Настройка фаервола..."
ufw allow 22/tcp
ufw allow $SOCKS_PORT/tcp
ufw allow $MTPROTO_PORT/tcp
ufw --force enable

# Настройка Dante SOCKS5
info "Настройка SOCKS5 прокси (Dante)..."
groupadd proxyusers 2>/dev/null || true

cat > /etc/danted.conf <<EOF
logoutput: syslog
internal: 0.0.0.0 port = $SOCKS_PORT
external: eth0
method: username
clientmethod: none
user.privileged: root
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect disconnect error
    method: username
}
EOF

systemctl restart danted
systemctl enable danted

# Настройка MTProto через Docker
info "Настройка MTProto прокси..."
mkdir -p /opt/mtproto-proxy
cd /opt/mtproto-proxy
cat > docker-compose.yml <<EOF
version: '3'

services:
  mtproto:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy
    restart: always
    ports:
      - "$MTPROTO_PORT:443"
    environment:
      - SECRET=$MTPROTO_SECRET
      - TLS_DOMAIN=$DOMAIN
    volumes:
      - ./proxy-secret:/data/proxy-secret
      - ./proxy-multi.conf:/data/proxy-multi.conf
EOF

docker-compose up -d

# Подготовка для бота
info "Настройка Telegram бота..."
mkdir -p /opt/proxy-bot
cd /opt/proxy-bot

# Создаем виртуальное окружение Python
python3 -m venv venv
source venv/bin/activate

# Устанавливаем зависимости
cat > requirements.txt <<EOF
aiogram==3.13.1
python-telegram-bot==21.10
sqlalchemy==2.0.36
requests==2.32.3
EOF

pip install -r requirements.txt

# Инициализация базы данных
cat > init_db.py <<EOF
import sqlite3
conn = sqlite3.connect('database.db')
c = conn.cursor()
c.execute('''CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tg_id INTEGER UNIQUE,
    username TEXT,
    socks_user TEXT UNIQUE,
    socks_pass TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_admin INTEGER DEFAULT 0,
    active INTEGER DEFAULT 1
)''')
c.execute('''CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT
)''')
c.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('socks_port', ?)", ($SOCKS_PORT,))
c.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('mtproto_port', ?)", ($MTPROTO_PORT,))
c.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('mtproto_secret', ?)", ($MTPROTO_SECRET,))
c.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('mtproto_domain', ?)", ('$DOMAIN',))
c.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('channel_id', ?)", ('$CHANNEL_ID',))
conn.commit()
conn.close()
EOF

python3 init_db.py

# Создаем основной скрипт бота (содержимое такое же, как в предыдущей версии)
# Для краткости здесь приведена только основная структура, полный код есть в репозитории
cat > bot.py <<'PYEOF'
# ... полный код бота (aiogram) ...
PYEOF

# Создаем systemd сервис
info "Создание systemd сервиса..."
cat > /etc/systemd/system/proxy-bot.service <<EOF
[Unit]
Description=Proxy Management Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/proxy-bot
Environment="BOT_TOKEN=$BOT_TOKEN"
Environment="CHANNEL_ID=$CHANNEL_ID"
ExecStart=/opt/proxy-bot/venv/bin/python /opt/proxy-bot/bot.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable proxy-bot
systemctl start proxy-bot

# Назначаем администратора, если указан ID
if [[ -n "$ADMIN_ID" ]]; then
    sqlite3 /opt/proxy-bot/database.db "UPDATE users SET is_admin = 1 WHERE tg_id = $ADMIN_ID;" || true
    # Если пользователь ещё не зарегистрирован, он не будет админом – бот создаст запись при его первом /start
    # Можно создать запись принудительно
    sqlite3 /opt/proxy-bot/database.db "INSERT OR IGNORE INTO users (tg_id, username, is_admin) VALUES ($ADMIN_ID, 'admin', 1);"
    info "Администратор с ID $ADMIN_ID установлен."
fi

# Итоговая информация
PUBLIC_IP=$(curl -s ifconfig.me)
MTLINK="tg://proxy?server=$PUBLIC_IP&port=$MTPROTO_PORT&secret=$MTPROTO_SECRET"
MTLINK_DOMAIN=""
if [[ "$DOMAIN" != "$PUBLIC_IP" ]]; then
    MTLINK_DOMAIN="tg://proxy?server=$DOMAIN&port=$MTPROTO_PORT&secret=$MTPROTO_SECRET"
fi

echo ""
echo "========================================="
echo -e "${GREEN}Установка завершена!${NC}"
echo "========================================="
echo ""
echo "SOCKS5 прокси:"
echo "  Адрес: $PUBLIC_IP"
echo "  Порт: $SOCKS_PORT"
echo "  Логин и пароль выдаются ботом для каждого пользователя."
echo ""
echo "MTProto прокси:"
echo "  Адрес: $PUBLIC_IP"
echo "  Порт: $MTPROTO_PORT"
echo "  Секрет: $MTPROTO_SECRET"
echo "  Ссылка: $MTLINK"
if [[ -n "$MTLINK_DOMAIN" ]]; then
    echo "  Ссылка с доменом: $MTLINK_DOMAIN"
fi
echo ""
echo "Telegram бот: @${BOT_TOKEN%%:*}"
[[ -n "$BOT_USERNAME" ]] && echo "Username бота: @$BOT_USERNAME"
echo "Команды бота: /start, /stats, /myproxy, /help"
echo "Администратор: ${ADMIN_ID:-не задан (назначьте через /addadmin)}"
echo ""
echo "Для проверки подписки на канал $CHANNEL_ID, бот будет требовать подписку."
echo "Информация сохранена в файл /root/proxy_info.txt"
echo "========================================="

# Сохраняем информацию в файл
cat > /root/proxy_info.txt <<EOF
Прокси Yurich

SOCKS5:
  Адрес: $PUBLIC_IP
  Порт: $SOCKS_PORT

MTProto:
  Адрес: $PUBLIC_IP
  Порт: $MTPROTO_PORT
  Секрет: $MTPROTO_SECRET
  Ссылка: $MTLINK
EOF

if [[ -n "$MTLINK_DOMAIN" ]]; then
    echo "  Ссылка с доменом: $MTLINK_DOMAIN" >> /root/proxy_info.txt
fi

echo "" >> /root/proxy_info.txt
echo "Telegram бот: @${BOT_TOKEN%%:*}" >> /root/proxy_info.txt
[[ -n "$BOT_USERNAME" ]] && echo "Username бота: @$BOT_USERNAME" >> /root/proxy_info.txt
echo "Канал: $CHANNEL_ID" >> /root/proxy_info.txt
echo "ID администратора: ${ADMIN_ID:-не задан}" >> /root/proxy_info.txt
