#!/bin/bash
# Прокси-менеджер для Telegram и WhatsApp с Telegram-ботом
# Автор: Юрич
# Версия: 3.5

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }

check_internet() {
    if curl -s --connect-timeout 5 https://ifconfig.me > /dev/null; then
        info "Интернет доступен"
    else
        warn "Не удаётся проверить интернет-соединение, продолжаем установку..."
    fi
}

print_banner() {
    clear
    printf "${CYAN}"
    printf '╔══════════════════════════════════════════════════════════════════════════╗\n'
    printf '║                                                                          ║\n'
    printf "${YELLOW}║     ██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗${CYAN}                     ║\n"
    printf "${YELLOW}║     ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝╚██╗ ██╔╝${CYAN}                     ║\n"
    printf "${YELLOW}║     ██████╔╝██████╔╝██║   ██║ ╚███╔╝  ╚████╔╝ ${CYAN}                     ║\n"
    printf "${YELLOW}║     ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗   ╚██╔╝  ${CYAN}                     ║\n"
    printf "${YELLOW}║     ██║     ██║  ██║╚██████╔╝██╔╝ ██╗   ██║   ${CYAN}                     ║\n"
    printf "${YELLOW}║     ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ${CYAN}                     ║\n"
    printf '║                                                                          ║\n'
    printf "${GREEN}║              ★  Юрич делает  ★  SOCKS5 + MTProto  ★${CYAN}               ║\n"
    printf "${YELLOW}║              Для Telegram и WhatsApp  |  v3.5${CYAN}                       ║\n"
    printf '║                                                                          ║\n'
    printf '╚══════════════════════════════════════════════════════════════════════════╝\n'
    printf "${NC}\n\n"
    sleep 1
}

print_banner
check_internet

if [[ $EUID -ne 0 ]]; then
    error "Скрипт должен выполняться от root. Используйте sudo."
fi

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

# Определение сетевого интерфейса
default_iface=$(ip route | grep default | awk '{print $5}' | head -1)
[[ -z "$default_iface" ]] && default_iface="eth0"
info "Обнаружен сетевой интерфейс: $default_iface"
read -p "Использовать этот интерфейс для прокси? (y/n, по умолчанию y): " change_iface
if [[ "$change_iface" == "n" ]]; then
    read -p "Введите имя интерфейса (например, eth0, ens3): " default_iface
fi

# Установка Docker (исправлено для Ubuntu 20.04)
if ! command -v docker &> /dev/null; then
    info "Установка Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    # Удаляем строку с docker-model-plugin из скрипта, если она там есть
    sed -i 's/docker-model-plugin//g' get-docker.sh
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

# Открываем порты в фаерволе
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

# Основной скрипт бота (полная версия с кнопками и админкой)
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
from aiogram.types import Message, InlineKeyboardMarkup, InlineKeyboardButton, CallbackQuery
from aiogram.enums import ChatMemberStatus
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.fsm.storage.memory import MemoryStorage

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

def main_keyboard(is_admin: bool = False):
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📋 Мои данные", callback_data="my_data"),
         InlineKeyboardButton(text="📊 Статистика", callback_data="stats")],
        [InlineKeyboardButton(text="📤 Поделиться", callback_data="share"),
         InlineKeyboardButton(text="❓ Помощь", callback_data="help")]
    ])
    if is_admin:
        keyboard.inline_keyboard.append([InlineKeyboardButton(text="👑 Админка", callback_data="admin_panel")])
    return keyboard

def admin_keyboard():
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="👥 Список пользователей", callback_data="list_users")],
        [InlineKeyboardButton(text="➕ Добавить пользователя", callback_data="add_user"),
         InlineKeyboardButton(text="➖ Удалить пользователя", callback_data="del_user")],
        [InlineKeyboardButton(text="⚙️ Настройки", callback_data="settings"),
         InlineKeyboardButton(text="📈 Онлайн статистика", callback_data="online_stats")],
        [InlineKeyboardButton(text="⬅️ Назад", callback_data="back_to_main")]
    ])
    return keyboard

class AddUserState(StatesGroup):
    waiting_for_username = State()

class DelUserState(StatesGroup):
    waiting_for_username = State()

@dp.message(CommandStart())
async def start_cmd(message: Message, state: FSMContext):
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
        f"⚙️ Для использования WhatsApp настройте SOCKS5 прокси в системе или приложении.\n\n"
        f"_ _ _ _ _ _ _ _ _ _\n"
        f"*Юрич делает*"
    )
    await message.answer(text, parse_mode="Markdown", reply_markup=main_keyboard(user['is_admin'] == 1))

@dp.callback_query(F.data == "check_sub")
async def check_sub_callback(callback: CallbackQuery, state: FSMContext):
    user_id = callback.from_user.id
    if await is_subscribed(user_id):
        await callback.message.delete()
        await start_cmd(callback.message, state)
    else:
        await callback.answer("Вы еще не подписались на канал!", show_alert=True)

@dp.callback_query(F.data == "my_data")
async def my_data_callback(callback: CallbackQuery):
    await callback.answer()
    await myproxy_cmd(callback.message)

@dp.callback_query(F.data == "stats")
async def stats_callback(callback: CallbackQuery):
    await callback.answer()
    await stats_cmd(callback.message)

@dp.callback_query(F.data == "share")
async def share_callback(callback: CallbackQuery):
    await callback.answer()
    await share_cmd(callback.message)

@dp.callback_query(F.data == "help")
async def help_callback(callback: CallbackQuery):
    await callback.answer()
    await help_cmd(callback.message)

@dp.callback_query(F.data == "admin_panel")
async def admin_panel_callback(callback: CallbackQuery):
    await callback.answer()
    await callback.message.edit_text(
        "👑 Админ-панель\nВыберите действие:",
        reply_markup=admin_keyboard()
    )

@dp.callback_query(F.data == "back_to_main")
async def back_to_main_callback(callback: CallbackQuery, state: FSMContext):
    await state.clear()
    await callback.answer()
    await start_cmd(callback.message, state)

@dp.callback_query(F.data == "list_users")
async def list_users_callback(callback: CallbackQuery):
    await callback.answer()
    await listusers_cmd(callback.message)

@dp.callback_query(F.data == "add_user")
async def add_user_callback(callback: CallbackQuery, state: FSMContext):
    await callback.answer()
    await callback.message.edit_text(
        "➕ Введите username нового пользователя (без @):",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="Отмена", callback_data="back_to_main")]])
    )
    await state.set_state(AddUserState.waiting_for_username)

@dp.message(AddUserState.waiting_for_username)
async def add_user_username(message: Message, state: FSMContext):
    username = message.text.strip().lstrip('@')
    user_id = message.from_user.id

    conn = get_db()
    admin = conn.execute("SELECT is_admin FROM users WHERE tg_id = ?", (user_id,)).fetchone()
    if not admin or admin['is_admin'] != 1:
        await message.answer("⛔ У вас нет прав администратора.")
        await state.clear()
        return

    try:
        user = await bot.get_chat(f"@{username}")
    except:
        await message.answer("❌ Пользователь не найден. Проверьте username.")
        await state.clear()
        return
    tg_id = user.id
    existing = conn.execute("SELECT * FROM users WHERE tg_id = ?", (tg_id,)).fetchone()
    if existing:
        await message.answer("❌ Пользователь уже зарегистрирован.")
        await state.clear()
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
    await state.clear()
    await start_cmd(message, state)

@dp.callback_query(F.data == "del_user")
async def del_user_callback(callback: CallbackQuery, state: FSMContext):
    await callback.answer()
    await callback.message.edit_text(
        "➖ Введите username пользователя для удаления (без @):",
        reply_markup=InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="Отмена", callback_data="back_to_main")]])
    )
    await state.set_state(DelUserState.waiting_for_username)

@dp.message(DelUserState.waiting_for_username)
async def del_user_username(message: Message, state: FSMContext):
    username = message.text.strip().lstrip('@')
    user_id = message.from_user.id

    conn = get_db()
    admin = conn.execute("SELECT is_admin FROM users WHERE tg_id = ?", (user_id,)).fetchone()
    if not admin or admin['is_admin'] != 1:
        await message.answer("⛔ У вас нет прав администратора.")
        await state.clear()
        return

    user = conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
    if not user:
        await message.answer("❌ Пользователь не найден.")
        await state.clear()
        return

    subprocess.run(['userdel', user['socks_user']], check=False)
    conn.execute("DELETE FROM users WHERE id = ?", (user['id'],))
    conn.commit()
    conn.close()

    await message.answer(f"✅ Пользователь @{username} удален.")
    await state.clear()
    await start_cmd(message, state)

@dp.callback_query(F.data == "settings")
async def settings_callback(callback: CallbackQuery):
    await callback.answer()
    await settings_cmd(callback.message)

@dp.callback_query(F.data == "online_stats")
async def online_stats_callback(callback: CallbackQuery):
    await callback.answer()
    await online_stats_cmd(callback.message)

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
        f"   Ссылка: {mtproto_link}\n\n"
        f"_ _ _ _ _ _ _ _ _ _\n"
        f"*Юрич делает*"
    )
    await message.answer(text, parse_mode="Markdown")

async def stats_cmd(message: Message):
    user_id = message.from_user.id
    if not await is_subscribed(user_id):
        await message.answer("🔒 Сначала подпишитесь на канал.", reply_markup=get_subscribe_keyboard())
        return

    traffic_summary = subprocess.getoutput("vnstat -i eth0 -s")
    socks_port = get_db().execute("SELECT value FROM settings WHERE key='socks_port'").fetchone()['value']
    active_conn = subprocess.getoutput(f"netstat -an | grep :{socks_port} | grep ESTABLISHED | wc -l")
    text = (
        f"📊 Статистика прокси:\n\n{traffic_summary}\n\n"
        f"Активных подключений к SOCKS5: {active_conn}\n\n"
        f"_ _ _ _ _ _ _ _ _ _\n"
        f"*Юрич делает*"
    )
    await message.answer(text, parse_mode="Markdown")

async def share_cmd(message: Message):
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
        f"🚀 *Мой прокси для Telegram и WhatsApp*\n\n"
        f"🌐 SOCKS5: `{public_ip}:{settings_dict['socks_port']}`\n"
        f"   Логин: `{user['socks_user']}`\n"
        f"   Пароль: `{user['socks_pass']}`\n\n"
        f"📱 MTProto: `{mtproto_link}`\n\n"
        f"🤖 Бот: @{os.getenv('BOT_TOKEN').split(':')[0]}\n"
        f"_ _ _ _ _ _ _ _ _ _\n"
        f"*Юрич делает*"
    )
    await message.answer(text, parse_mode="Markdown")

async def help_cmd(message: Message):
    text = (
        "📚 *Доступные команды:*\n\n"
        "/start – регистрация и получение данных прокси\n"
        "/stats – общая статистика\n"
        "/myproxy – ваши данные прокси\n"
        "/help – это сообщение\n\n"
        "🔘 *Используйте кнопки под сообщениями для навигации.*\n\n"
        "_ _ _ _ _ _ _ _ _ _\n"
        "*Юрич делает*"
    )
    await message.answer(text, parse_mode="Markdown")

async def settings_cmd(message: Message):
    user_id = message.from_user.id
    conn = get_db()
    admin = conn.execute("SELECT is_admin FROM users WHERE tg_id = ?", (user_id,)).fetchone()
    conn.close()
    if not admin or admin['is_admin'] != 1:
        await message.answer("⛔ У вас нет прав администратора.")
        return

    conn = get_db()
    settings = conn.execute("SELECT key, value FROM settings").fetchall()
    conn.close()
    text = "⚙️ Текущие настройки:\n\n"
    for s in settings:
        text += f"**{s['key']}**: `{s['value']}`\n"
    text += "\n_ _ _ _ _ _ _ _ _ _\n*Юрич делает*"
    await message.answer(text, parse_mode="Markdown")

async def listusers_cmd(message: Message):
    user_id = message.from_user.id
    conn = get_db()
    admin = conn.execute("SELECT is_admin FROM users WHERE tg_id = ?", (user_id,)).fetchone()
    if not admin or admin['is_admin'] != 1:
        await message.answer("⛔ У вас нет прав администратора.")
        return

    users = conn.execute("SELECT tg_id, username, created_at FROM users").fetchall()
    conn.close()
    if not users:
        await message.answer("Нет зарегистрированных пользователей.")
        return
    text = "📋 Список пользователей:\n\n"
    for u in users:
        text += f"👤 @{u['username']} (ID: {u['tg_id']}) - зарегистрирован {u['created_at']}\n"
    text += "\n_ _ _ _ _ _ _ _ _ _\n*Юрич делает*"
    await message.answer(text, parse_mode="Markdown")

async def online_stats_cmd(message: Message):
    user_id = message.from_user.id
    conn = get_db()
    admin = conn.execute("SELECT is_admin FROM users WHERE tg_id = ?", (user_id,)).fetchone()
    if not admin or admin['is_admin'] != 1:
        await message.answer("⛔ У вас нет прав администратора.")
        return

    socks_port = conn.execute("SELECT value FROM settings WHERE key='socks_port'").fetchone()['value']
    conn.close()
    active_conn = subprocess.getoutput(f"netstat -an | grep :{socks_port} | grep ESTABLISHED | wc -l")
    text = f"📈 *Онлайн статистика*\n\nАктивных подключений к SOCKS5: {active_conn}\n\n_ _ _ _ _ _ _ _ _ _\n*Юрич делает*"
    await message.answer(text, parse_mode="Markdown")

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

# Установка администратора
if [[ -n "$ADMIN_ID" ]]; then
    sqlite3 /opt/proxy-bot/database.db "INSERT OR IGNORE INTO users (tg_id, username, is_admin) VALUES ($ADMIN_ID, 'admin', 1);"
    info "Администратор с ID $ADMIN_ID установлен."
fi

# Создание консольной команды для управления
cat > /usr/local/bin/yurich-proxy <<'EOF'
#!/bin/bash
case "$1" in
    status)
        echo -e "\033[0;36mПрокси-менеджер\033[0m"
        systemctl status proxy-bot --no-pager | grep -E "Active:|loaded" || echo "Бот не запущен"
        systemctl status danted --no-pager | grep -E "Active:|loaded" || echo "SOCKS5 не запущен"
        docker ps --filter "name=mtproto-proxy" --format "table {{.Names}}\t{{.Status}}" || echo "MTProto не запущен"
        ;;
    restart)
        systemctl restart proxy-bot
        systemctl restart danted
        cd /opt/mtproto-proxy && docker-compose restart
        echo "✅ Все сервисы перезапущены"
        ;;
    logs)
        journalctl -u proxy-bot -n 50 --no-pager
        ;;
    update)
        curl -sSL https://raw.githubusercontent.com/Pykucyka/yurichdelaetproxy/main/yurich_proxy.sh -o /tmp/update.sh
        bash /tmp/update.sh --skip-questions
        rm /tmp/update.sh
        ;;
    help|--help|-h)
        echo "Использование: yurich-proxy {status|restart|logs|update|help}"
        echo "  status   - показать статус всех сервисов"
        echo "  restart  - перезапустить все сервисы"
        echo "  logs     - показать последние логи бота"
        echo "  update   - обновить скрипт (сохраняет настройки)"
        echo "  help     - эта справка"
        ;;
    *)
        echo "Неизвестная команда: $1"
        echo "Используйте: yurich-proxy help"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/yurich-proxy

# Итоговая информация
PUBLIC_IP=$(curl -s ifconfig.me)
MTLINK="tg://proxy?server=$PUBLIC_IP&port=$MTPROTO_PORT&secret=$MTPROTO_SECRET"
MTLINK_DOMAIN=""
if [[ "$DOMAIN" != "$PUBLIC_IP" ]]; then
    MTLINK_DOMAIN="tg://proxy?server=$DOMAIN&port=$MTPROTO_PORT&secret=$MTPROTO_SECRET"
fi

echo ""
echo "========================================="
printf "${GREEN}✅ Установка завершена!${NC}\n"
echo "========================================="
echo ""
echo "🌐 SOCKS5 прокси: $PUBLIC_IP:$SOCKS_PORT"
echo "📱 MTProto прокси: $PUBLIC_IP:$MTPROTO_PORT"
echo "🔗 Ссылка MTProto: $MTLINK"
[[ -n "$MTLINK_DOMAIN" ]] && echo "🔗 Ссылка с доменом: $MTLINK_DOMAIN"
echo ""
echo "🤖 Telegram бот: @${BOT_TOKEN%%:*}"
echo "📋 Бот использует кнопки:"
echo "   • Главное меню: Мои данные, Статистика, Поделиться, Помощь"
echo "   • Для администраторов: Админка → управление пользователями, настройки, онлайн-статистика"
echo "👑 Администратор: ${ADMIN_ID:-не задан (назначьте через /addadmin)}"
echo ""
echo "📄 Информация сохранена в /root/proxy_info.txt"
echo "🛠 Команды управления: yurich-proxy {status|restart|logs|update|help}"
echo "========================================="

# Сохраняем информацию
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
