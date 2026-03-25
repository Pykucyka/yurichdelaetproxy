#!/bin/bash
# Прокси-менеджер с поддержкой Docker (SOCKS5 + MTProto)
# Автор: Юрич
# Версия: 3.2

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Функция для проверки подключения к интернету
check_internet() {
    if ! curl -s --head https://google.com | head -n 1 | grep "200 OK" > /dev/null; then
        error "Нет подключения к интернету. Проверьте сеть."
    fi
}

print_banner() {
    clear
    echo -e "${CYAN}"
    echo '╔══════════════════════════════════════════════════════════════════════════╗'
    echo '║                                                                          ║'
    echo -e '║     ${YELLOW}██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗${CYAN}                     ║'
    echo -e '║     ${YELLOW}██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝╚██╗ ██╔╝${CYAN}                     ║'
    echo -e '║     ${YELLOW}██████╔╝██████╔╝██║   ██║ ╚███╔╝  ╚████╔╝ ${CYAN}                     ║'
    echo -e '║     ${YELLOW}██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗   ╚██╔╝  ${CYAN}                     ║'
    echo -e '║     ${YELLOW}██║     ██║  ██║╚██████╔╝██╔╝ ██╗   ██║   ${CYAN}                     ║'
    echo -e '║     ${YELLOW}╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ${CYAN}                     ║'
    echo '║                                                                          ║'
    echo -e "║              ${GREEN}★  PROXY DOCKER  ★  SOCKS5 + MTProto  ★${CYAN}               ║"
    echo -e "║              ${YELLOW}Для Telegram и WhatsApp  |  v3.2${CYAN}                       ║"
    echo '║                                                                          ║'
    echo '╚══════════════════════════════════════════════════════════════════════════╝'
    echo -e "${NC}"
    echo ""
    sleep 1
}

print_banner
check_internet

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

# Определение сетевого интерфейса для vnstat и Dante
default_iface=$(ip route | grep default | awk '{print $5}' | head -1)
if [[ -z "$default_iface" ]]; then
    default_iface="eth0"
fi
info "Обнаружен сетевой интерфейс: $default_iface"
read -p "Использовать этот интерфейс для прокси? (y/n, по умолчанию y): " change_iface
if [[ "$change_iface" == "n" ]]; then
    read -p "Введите имя интерфейса (например, eth0, ens3): " default_iface
fi

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

MTPROTO_SECRET=$(head -c 16 /dev/urandom | xxd -ps)
info "Сгенерирован секрет MTProto: $MTPROTO_SECRET"

echo ""
read -p "Ваш Telegram ID (администратор, можно узнать у @userinfobot): " ADMIN_ID
if [[ -z "$ADMIN_ID" ]]; then
    warn "ID администратора не указан. Вы сможете назначить админа позже через бота командой /addadmin."
fi

echo ""
echo "-----------------------------"
echo "Токен бота: $BOT_TOKEN"
[[ -n "$BOT_USERNAME" ]] && echo "Username бота: @$BOT_USERNAME"
echo "Канал: $CHANNEL_ID"
echo "Домен: $DOMAIN"
echo "Интерфейс: $default_iface"
echo "SOCKS5 порт: $SOCKS_PORT"
echo "MTProto порт: $MTPROTO_PORT"
echo "MTProto секрет: $MTPROTO_SECRET"
echo "ID администратора: ${ADMIN_ID:-не задан}"
echo "-----------------------------"
read -p "Продолжить? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && error "Установка отменена."

ufw allow 22/tcp
ufw allow $SOCKS_PORT/tcp
ufw allow $MTPROTO_PORT/tcp
ufw --force enable

# Настройка Dante SOCKS5 с указанием интерфейса
info "Настройка SOCKS5 прокси (Dante)..."
groupadd proxyusers 2>/dev/null || true

cat > /etc/danted.conf <<EOF
logoutput: syslog
internal: 0.0.0.0 port = $SOCKS_PORT
external: $default_iface
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

python3 -m venv venv
source venv/bin/activate

cat > requirements.txt <<EOF
aiogram==3.13.1
python-telegram-bot==21.10
sqlalchemy==2.0.36
requests==2.32.3
EOF

pip install -r requirements.txt

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

# Создаём бота (тот же код, что и раньше)
cat > bot.py <<'PYEOF'
import asyncio
import logging
import sqlite3
import subprocess
import os
import secrets
import string
from datetime import datetime
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import Command, CommandObject, CommandStart
from aiogram.types import Message, InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.enums import ChatMemberStatus
from aiogram.fsm.context import FSMContext
from aiogram.fsm.storage.memory import MemoryStorage

# Конфигурация из переменных окружения
BOT_TOKEN = os.getenv("BOT_TOKEN")
CHANNEL_ID = os.getenv("CHANNEL_ID")

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher(storage=MemoryStorage())
logging.basicConfig(level=logging.INFO)

def get_db():
    conn = sqlite3.connect('/opt/proxy-bot/database.db')
    conn.row_factory = sqlite3.Row
    return conn

async def is_subscribed(user_id: int) -> bool:
    try:
        member = await bot.get_chat_member(CHANNEL_ID, user_id)
        return member.status in [ChatMemberStatus.MEMBER, ChatMemberStatus.ADMINISTRATOR, ChatMemberStatus.CREATOR]
    except:
        return False

def get_subscribe_keyboard():
    url = CHANNEL_ID if CHANNEL_ID.startswith('@') else f'https://t.me/{CHANNEL_ID}'
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📢 Подписаться на канал", url=url)],
        [InlineKeyboardButton(text="✅ Проверить подписку", callback_data="check_sub")]
    ])
    return keyboard

@dp.message(CommandStart())
async def start_cmd(message: Message):
    user_id = message.from_user.id
    if not await is_subscribed(user_id):
        await message.answer(
            "🔒 Для использования бота необходимо подписаться на наш канал!\n\n"
            "После подписки нажмите кнопку 'Проверить подписку'.",
            reply_markup=get_subscribe_keyboard()
        )
        return

    conn = get_db()
    user = conn.execute("SELECT * FROM users WHERE tg_id = ?", (user_id,)).fetchone()
    if not user:
        socks_user = f"user_{user_id}"
        socks_pass = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(12))
        subprocess.run(['useradd', '-g', 'proxyusers', '-s', '/bin/false', socks_user], check=False)
        subprocess.run(['echo', f'{socks_user}:{socks_pass}', '|', 'chpasswd'], shell=True, check=False)
        conn.execute(
            "INSERT INTO users (tg_id, username, socks_user, socks_pass, is_admin) VALUES (?, ?, ?, ?, ?)",
            (user_id, message.from_user.username, socks_user, socks_pass, 0)
        )
        conn.commit()
        user = conn.execute("SELECT * FROM users WHERE tg_id = ?", (user_id,)).fetchone()

    settings = conn.execute("SELECT key, value FROM settings").fetchall()
    settings_dict = {row['key']: row['value'] for row in settings}
    conn.close()

    public_ip = subprocess.getoutput("curl -s ifconfig.me")
    mtproto_link = f"tg://proxy?server={public_ip}&port={settings_dict['mtproto_port']}&secret={settings_dict['mtproto_secret']}"
    if settings_dict['mtproto_domain'] != public_ip:
        mtproto_link_domain = f"tg://proxy?server={settings_dict['mtproto_domain']}&port={settings_dict['mtproto_port']}&secret={settings_dict['mtproto_secret']}"
        domain_text = f"\n   Ссылка с доменом: {mtproto_link_domain}"
    else:
        domain_text = ""

    text = (
        f"✅ Вы зарегистрированы!\n\n"
        f"🌐 SOCKS5 прокси:\n"
        f"   Сервер: {public_ip}\n"
        f"   Порт: {settings_dict['socks_port']}\n"
        f"   Логин: {user['socks_user']}\n"
        f"   Пароль: {user['socks_pass']}\n\n"
        f"📱 MTProto прокси для Telegram:\n"
        f"   Сервер: {public_ip}\n"
        f"   Порт: {settings_dict['mtproto_port']}\n"
        f"   Секрет: {settings_dict['mtproto_secret']}\n"
        f"   Ссылка: {mtproto_link}{domain_text}\n\n"
        f"⚙️ Для использования WhatsApp настройте SOCKS5 прокси в системе или приложении."
    )
    await message.answer(text)

@dp.callback_query(F.data == "check_sub")
async def check_sub_callback(callback: types.CallbackQuery):
    user_id = callback.from_user.id
    if await is_subscribed(user_id):
        await callback.message.delete()
        await start_cmd(callback.message)
    else:
        await callback.answer("Вы еще не подписались на канал!", show_alert=True)

@dp.message(Command("stats"))
async def stats_cmd(message: Message):
    user_id = message.from_user.id
    if not await is_subscribed(user_id):
        await message.answer("🔒 Сначала подпишитесь на канал.", reply_markup=get_subscribe_keyboard())
        return

    traffic_summary = subprocess.getoutput("vnstat -i eth0 -s")
    socks_port = get_db().execute("SELECT value FROM settings WHERE key='socks_port'").fetchone()['value']
    active_conn = subprocess.getoutput(f"netstat -an | grep :{socks_port} | grep ESTABLISHED | wc -l")
    text = f"📊 Статистика прокси:\n\n{traffic_summary}\n\nАктивных подключений к SOCKS5: {active_conn}"
    await message.answer(text)

@dp.message(Command("myproxy"))
async def myproxy_cmd(message: Message):
    user_id = message.from_user.id
    if not await is_subscribed(user_id):
        await message.answer("🔒 Сначала подпишитесь на канал.", reply_markup=get_subscribe_keyboard())
        return

    conn = get_db()
    user = conn.execute("SELECT * FROM users WHERE tg_id = ?", (user_id,)).fetchone()
    if not user:
        await message.answer("❌ Вы не зарегистрированы. Используйте /start для регистрации.")
        return
    settings = conn.execute("SELECT key, value FROM settings").fetchall()
    settings_dict = {row['key']: row['value'] for row in settings}
    conn.close()

    public_ip = subprocess.getoutput("curl -s ifconfig.me")
    mtproto_link = f"tg://proxy?server={public_ip}&port={settings_dict['mtproto_port']}&secret={settings_dict['mtproto_secret']}"
    text = (
        f"🌐 Ваши данные для прокси:\n\n"
        f"SOCKS5:\n"
        f"   Сервер: {public_ip}\n"
        f"   Порт: {settings_dict['socks_port']}\n"
        f"   Логин: {user['socks_user']}\n"
        f"   Пароль: {user['socks_pass']}\n\n"
        f"MTProto:\n"
        f"   Сервер: {public_ip}\n"
        f"   Порт: {settings_dict['mtproto_port']}\n"
        f"   Секрет: {settings_dict['mtproto_secret']}\n"
        f"   Ссылка: {mtproto_link}"
    )
    await message.answer(text)

def is_admin(user_id: int) -> bool:
    conn = get_db()
    admin = conn.execute("SELECT is_admin FROM users WHERE tg_id = ?", (user_id,)).fetchone()
    conn.close()
    return admin and admin['is_admin'] == 1

@dp.message(Command("adduser"))
async def adduser_cmd(message: Message, command: CommandObject):
    user_id = message.from_user.id
    if not is_admin(user_id):
        await message.answer("⛔ У вас нет прав администратора.")
        return
    args = command.args
    if not args:
        await message.answer("Укажите username нового пользователя. Пример: /adduser @username")
        return
    username = args.strip().lstrip('@')
    try:
        user = await bot.get_chat(f"@{username}")
    except:
        await message.answer("Пользователь не найден. Убедитесь, что username правильный.")
        return
    tg_id = user.id
    conn = get_db()
    existing = conn.execute("SELECT * FROM users WHERE tg_id = ?", (tg_id,)).fetchone()
    if existing:
        await message.answer("Пользователь уже зарегистрирован.")
        return
    socks_user = f"user_{tg_id}"
    socks_pass = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(12))
    subprocess.run(['useradd', '-g', 'proxyusers', '-s', '/bin/false', socks_user], check=False)
    subprocess.run(['echo', f'{socks_user}:{socks_pass}', '|', 'chpasswd'], shell=True, check=False)
    conn.execute(
        "INSERT INTO users (tg_id, username, socks_user, socks_pass, is_admin) VALUES (?, ?, ?, ?, 0)",
        (tg_id, username, socks_user, socks_pass)
    )
    conn.commit()
    conn.close()
    await message.answer(f"✅ Пользователь @{username} добавлен. Он сможет получить свои данные через /start.")

@dp.message(Command("deluser"))
async def deluser_cmd(message: Message, command: CommandObject):
    user_id = message.from_user.id
    if not is_admin(user_id):
        await message.answer("⛔ У вас нет прав администратора.")
        return
    args = command.args
    if not args:
        await message.answer("Укажите username пользователя для удаления. Пример: /deluser @username")
        return
    username = args.strip().lstrip('@')
    conn = get_db()
    user = conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
    if not user:
        await message.answer("Пользователь не найден.")
        return
    subprocess.run(['userdel', user['socks_user']], check=False)
    conn.execute("DELETE FROM users WHERE id = ?", (user['id'],))
    conn.commit()
    conn.close()
    await message.answer(f"✅ Пользователь @{username} удален.")

@dp.message(Command("listusers"))
async def listusers_cmd(message: Message):
    user_id = message.from_user.id
    if not is_admin(user_id):
        await message.answer("⛔ У вас нет прав администратора.")
        return
    conn = get_db()
    users = conn.execute("SELECT tg_id, username, created_at FROM users").fetchall()
    conn.close()
    if not users:
        await message.answer("Нет зарегистрированных пользователей.")
        return
    text = "📋 Список пользователей:\n\n"
    for u in users:
        text += f"👤 @{u['username']} (ID: {u['tg_id']}) - зарегистрирован {u['created_at']}\n"
    await message.answer(text)

@dp.message(Command("settings"))
async def settings_cmd(message: Message):
    user_id = message.from_user.id
    if not is_admin(user_id):
        await message.answer("⛔ У вас нет прав администратора.")
        return
    conn = get_db()
    settings = conn.execute("SELECT key, value FROM settings").fetchall()
    conn.close()
    text = "⚙️ Текущие настройки:\n\n"
    for s in settings:
        text += f"**{s['key']}**: `{s['value']}`\n"
    await message.answer(text, parse_mode="Markdown")

@dp.message(Command("setsocksport"))
async def set_socks_port(message: Message, command: CommandObject):
    user_id = message.from_user.id
    if not is_admin(user_id):
        await message.answer("⛔ У вас нет прав администратора.")
        return
    args = command.args
    if not args or not args.isdigit():
        await message.answer("Укажите новый порт. Пример: /setsocksport 1080")
        return
    new_port = int(args)
    subprocess.run(f"sed -i 's/port = [0-9]\\+/port = {new_port}/' /etc/danted.conf", shell=True)
    subprocess.run("systemctl restart danted", shell=True)
    subprocess.run(f"ufw allow {new_port}/tcp", shell=True)
    conn = get_db()
    conn.execute("UPDATE settings SET value = ? WHERE key = 'socks_port'", (new_port,))
    conn.commit()
    conn.close()
    await message.answer(f"✅ Порт SOCKS5 изменен на {new_port}.")

@dp.message(Command("setmtport"))
async def set_mt_port(message: Message, command: CommandObject):
    user_id = message.from_user.id
    if not is_admin(user_id):
        await message.answer("⛔ У вас нет прав администратора.")
        return
    args = command.args
    if not args or not args.isdigit():
        await message.answer("Укажите новый порт. Пример: /setmtport 443")
        return
    new_port = int(args)
    os.chdir('/opt/mtproto-proxy')
    subprocess.run(f"sed -i 's/\"[0-9]\\+:443\"/\"{new_port}:443\"/' docker-compose.yml", shell=True)
    subprocess.run("docker-compose down && docker-compose up -d", shell=True)
    subprocess.run(f"ufw allow {new_port}/tcp", shell=True)
    conn = get_db()
    conn.execute("UPDATE settings SET value = ? WHERE key = 'mtproto_port'", (new_port,))
    conn.commit()
    conn.close()
    await message.answer(f"✅ Порт MTProto изменен на {new_port}.")

@dp.message(Command("setmtsecret"))
async def set_mt_secret(message: Message, command: CommandObject):
    user_id = message.from_user.id
    if not is_admin(user_id):
        await message.answer("⛔ У вас нет прав администратора.")
        return
    args = command.args
    if not args or len(args) != 32 or not all(c in '0123456789abcdef' for c in args):
        await message.answer("Укажите новый секрет (32 hex символа). Пример: /setmtsecret 0123456789abcdef0123456789abcdef")
        return
    new_secret = args
    os.chdir('/opt/mtproto-proxy')
    subprocess.run(f"sed -i 's/SECRET=.*/SECRET={new_secret}/' docker-compose.yml", shell=True)
    subprocess.run("docker-compose down && docker-compose up -d", shell=True)
    conn = get_db()
    conn.execute("UPDATE settings SET value = ? WHERE key = 'mtproto_secret'", (new_secret,))
    conn.commit()
    conn.close()
    await message.answer(f"✅ Секрет MTProto изменен.")

@dp.message(Command("addadmin"))
async def addadmin_cmd(message: Message, command: CommandObject):
    user_id = message.from_user.id
    if not is_admin(user_id):
        await message.answer("⛔ У вас нет прав администратора.")
        return
    args = command.args
    if not args:
        await message.answer("Укажите username нового администратора. Пример: /addadmin @username")
        return
    username = args.strip().lstrip('@')
    conn = get_db()
    user = conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
    if not user:
        await message.answer("Пользователь не найден. Сначала зарегистрируйте его через /start или /adduser.")
        return
    conn.execute("UPDATE users SET is_admin = 1 WHERE id = ?", (user['id'],))
    conn.commit()
    conn.close()
    await message.answer(f"✅ Пользователь @{username} теперь администратор.")

@dp.message(Command("help"))
async def help_cmd(message: Message):
    user_id = message.from_user.id
    admin = is_admin(user_id)
    text = (
        "📚 Доступные команды:\n\n"
        "/start – регистрация и получение данных прокси\n"
        "/stats – общая статистика\n"
        "/myproxy – ваши данные прокси\n"
        "/help – это сообщение\n"
    )
    if admin:
        text += (
            "\n👑 Админ-команды:\n"
            "/adduser @username – добавить пользователя\n"
            "/deluser @username – удалить пользователя\n"
            "/listusers – список пользователей\n"
            "/setsocksport <порт> – изменить порт SOCKS5\n"
            "/setmtport <порт> – изменить порт MTProto\n"
            "/setmtsecret <32hex> – изменить секрет MTProto\n"
            "/addadmin @username – дать права админа\n"
        )
    await message.answer(text)

async def main():
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
PYEOF

# Создание systemd сервиса
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

if [[ -n "$ADMIN_ID" ]]; then
    sqlite3 /opt/proxy-bot/database.db "INSERT OR IGNORE INTO users (tg_id, username, is_admin) VALUES ($ADMIN_ID, 'admin', 1);"
    info "Администратор с ID $ADMIN_ID установлен."
fi

PUBLIC_IP=$(curl -s ifconfig.me)
MTLINK="tg://proxy?server=$PUBLIC_IP&port=$MTPROTO_PORT&secret=$MTPROTO_SECRET"
MTLINK_DOMAIN=""
if [[ "$DOMAIN" != "$PUBLIC_IP" ]]; then
    MTLINK_DOMAIN="tg://proxy?server=$DOMAIN&port=$MTPROTO_PORT&secret=$MTPROTO_SECRET"
fi

echo ""
echo "========================================="
echo -e "${GREEN}✅ Установка завершена!${NC}"
echo "========================================="
echo ""
echo "🌐 SOCKS5 прокси: $PUBLIC_IP:$SOCKS_PORT"
echo "📱 MTProto прокси: $PUBLIC_IP:$MTPROTO_PORT"
echo "🔗 Ссылка MTProto: $MTLINK"
[[ -n "$MTLINK_DOMAIN" ]] && echo "🔗 Ссылка с доменом: $MTLINK_DOMAIN"
echo ""
echo "🤖 Telegram бот: @${BOT_TOKEN%%:*}"
echo "📋 Команды бота: /start, /stats, /myproxy, /help"
echo "👑 Администратор: ${ADMIN_ID:-не задан}"
echo ""
echo "📄 Информация сохранена в /root/proxy_info.txt"
echo "========================================="

cat > /root/proxy_info.txt <<EOF
Прокси-сервер (Docker)

SOCKS5:
  Адрес: $PUBLIC_IP
  Порт: $SOCKS_PORT
  Логин и пароль выдаются ботом.

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
echo "Канал: $CHANNEL_ID" >> /root/proxy_info.txt
