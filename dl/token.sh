#!/bin/bash
# Меняет токен основного бота (после /revoke в @BotFather). Токен можно передать или вставить по запросу.
#   curl -fsSL "https://hikingerop.github.io/dl/token.sh?$(date +%s)" | bash
set -euo pipefail
cd /opt/vpn-bot
TOKEN="${1:-}"
if [ -z "$TOKEN" ]; then
  read -rp "Вставь новый токен основного бота и нажми Enter: " TOKEN < /dev/tty
fi
TOKEN=$(echo "$TOKEN" | tr -d ' \r\n')
if ! [[ "$TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]]; then
  echo "❌ Это не похоже на токен бота (вид: 123456:ABC…)"; exit 1
fi
if grep -q "^ADMIN_BOT_TOKEN=$TOKEN$" .env; then
  echo "❌ Это токен админки, а нужен токен основного бота (@MeridaVpn_Bot)."; exit 1
fi
NAME=$(curl -fsS -m 15 "https://api.telegram.org/bot$TOKEN/getMe" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["username"])' 2> /dev/null) \
  || { echo "❌ Telegram не принял токен — проверь, что скопирован целиком"; exit 1; }
if grep -q "^BOT_TOKEN=" .env; then sed -i "s|^BOT_TOKEN=.*|BOT_TOKEN=$TOKEN|" .env; else echo "BOT_TOKEN=$TOKEN" >> .env; fi
systemctl restart vpn-bot
sleep 6
if systemctl is-active vpn-bot > /dev/null; then
  echo "✅ Токен заменён, бот @$NAME работает. Старый токен больше ничего не может."
else
  echo "❌ Бот не запустился:"; journalctl -u vpn-bot -n 12 --no-pager -o cat
fi
