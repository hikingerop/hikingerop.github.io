#!/bin/bash
# На основном сервере: подключить входной сервер. Обновляет код бота, адрес в ключах и в приложении.
#   curl -fsSL https://hikingerop.github.io/dl/entry.sh | bash -s -- IP_ВХОДНОГО_СЕРВЕРА
set -euo pipefail
ENTRY=${1:?Укажите IP входного сервера}
cd /opt/vpn-bot

echo "→ Обновляю код бота…"
curl -fsSL https://hikingerop.github.io/dl/merida-bot.tar.gz | tar xz
venv/bin/pip install -q -r requirements.txt

set_env() {
  if grep -q "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else echo "$1=$2" >> .env; fi
}
set_env ENTRY_HOST "$ENTRY"
set_env RELAY_IPS "$ENTRY"

systemctl restart vpn-bot
sleep 6
echo "--------------------------------------------"
systemctl is-active vpn-bot > /dev/null && echo "✅ Готово: люди подключаются через $ENTRY" || echo "❌ Бот не запустился:"
journalctl -u vpn-bot -n 8 --no-pager -o cat | grep -E "API_URL|API_PIN|ERROR|Error" || true
