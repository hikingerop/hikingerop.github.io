#!/bin/bash
# Подключает бота-админку (список аккаунтов, выдача подписки кнопками) и обновляет код бота.
#   curl -fsSL "https://hikingerop.github.io/dl/admin-bot.sh?$(date +%s)" | bash -s ТОКЕН
# ТОКЕН — от @BotFather для нового бота (не основного). Бот отвечает только админам из ADMIN_IDS.
set -euo pipefail
TOKEN="${1:-}"
cd /opt/vpn-bot

if ! [[ "$TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]]; then
  echo "❌ Нужен токен бота-админки: … | bash -s 123456:ABC…"; exit 1
fi
if grep -q "^BOT_TOKEN=$TOKEN$" .env; then
  echo "❌ Это токен основного бота. Создай в @BotFather нового бота и пришли его токен."; exit 1
fi
NAME=$(curl -fsS -m 15 "https://api.telegram.org/bot$TOKEN/getMe" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["username"])' 2> /dev/null) \
  || { echo "❌ Telegram не принял токен — проверь, что скопирован целиком"; exit 1; }

set_env() {
  if grep -q "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else echo "$1=$2" >> .env; fi
}
set_env ADMIN_BOT_TOKEN "$TOKEN"
echo "→ Админка: @$NAME"

echo "→ Обновляю код бота…"
curl -fsSL "https://hikingerop.github.io/dl/merida-bot.tar.gz?$(date +%s)" | tar xz
venv/bin/pip install -q -r requirements.txt
systemctl restart vpn-bot
sleep 6
if systemctl is-active vpn-bot > /dev/null; then
  echo "✅ Готово. Открой @$NAME в Telegram и нажми «Запустить»."
else
  echo "❌ Бот не запустился:"; journalctl -u vpn-bot -n 12 --no-pager -o cat
fi
