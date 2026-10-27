#!/bin/bash
# Установка (и обновление) бота Merida VPN на сервер одной командой:
#   curl -fsSL https://hikingerop.github.io/dl/install.sh | bash -s -- ТОКЕН_БОТА TELEGRAM_ID ПАРОЛЬ_ПАНЕЛИ [ЛОГИН_ПАНЕЛИ] [ID_ИНБАУНДА]
# Повторный запуск обновляет код бота, а настройки (.env) не трогает.
set -euo pipefail

TOKEN="${1:?Укажите токен бота}"
ADMIN="${2:?Укажите ваш Telegram ID}"
PANEL_PASS="${3:?Укажите пароль от панели 3x-ui}"
PANEL_USER="${4:-merida}"
INBOUND="${5:-1}"
DIR=/opt/vpn-bot
BASE=https://hikingerop.github.io/dl

echo "→ Ставлю Python и нужные программы…"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv openssl curl > /dev/null

echo "→ Скачиваю бота…"
mkdir -p "$DIR"
cd "$DIR"
curl -fsSL "https://hikingerop.github.io/dl/fetch-code.sh?$(date +%s)" | bash
python3 -m venv venv
venv/bin/pip install -q --upgrade pip
venv/bin/pip install -q -r requirements.txt

if [ ! -f .env ]; then
  echo "→ Записываю настройки…"
  IP=$(curl -fsS -m 10 https://api.ipify.org || hostname -I | awk '{print $1}')
  cat > .env <<ENV
BOT_TOKEN='$TOKEN'
ADMIN_IDS=$ADMIN
ADMIN_USERNAME=
PANEL_URL=http://127.0.0.1:2053
PANEL_USERNAME='$PANEL_USER'
PANEL_PASSWORD='$PANEL_PASS'
PANEL_VERIFY_SSL=false
INBOUND_ID=$INBOUND
SERVER_HOST=$IP
KEY_NAME='🇳🇱 Нидерланды'
SERVICE_NAME='Merida VPN'
TRIAL_DAYS=15
TRIAL_GB=5
PRICE_RUB=50
PAID_DAYS=30
REMIND_HOURS=12
APP_API=true
API_PORT=8443
PAGE_PORT=8080
APP_ID=com.merida.vpn
TRIAL_PER_IP_DAY=3
GOOGLE_CLIENT_ID=
YOOKASSA_SHOP_ID=
YOOKASSA_SECRET_KEY=
ENV
  chmod 600 .env
else
  echo "→ Настройки (.env) уже есть — оставляю как были"
fi

if command -v ufw > /dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 443/tcp > /dev/null; ufw allow 8443/tcp > /dev/null; ufw allow 8080/tcp > /dev/null
fi

echo "→ Запускаю бота…"
cp vpn-bot.service /etc/systemd/system/vpn-bot.service
systemctl daemon-reload
systemctl enable vpn-bot > /dev/null 2>&1
systemctl restart vpn-bot
sleep 6
echo "--------------------------------------------"
systemctl is-active vpn-bot && echo "✅ Бот работает. Напишите ему /start в Telegram." || echo "❌ Бот не запустился — пришлите скриншот того, что ниже:"
journalctl -u vpn-bot -n 12 --no-pager -o cat
