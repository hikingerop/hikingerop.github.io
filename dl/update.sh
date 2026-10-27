#!/bin/bash
# Обновляет код бота на основном сервере (настройки .env и ключи не трогает).
#   curl -fsSL "https://hikingerop.github.io/dl/update.sh?$(date +%s)" | bash
# Код лежит на сайте зашифрованным: расшифровать его может только этот сервер своим ключом
# (/opt/vpn-bot/.update_key.pem, создаёт update-key.sh).
set -euo pipefail
cd /opt/vpn-bot
curl -fsSL "https://hikingerop.github.io/dl/fetch-code.sh?$(date +%s)" | bash
venv/bin/pip install -q -r requirements.txt
systemctl restart vpn-bot
sleep 6
systemctl is-active vpn-bot > /dev/null && echo "✅ Бот обновлён и работает" || { echo "❌ Бот не запустился:"; journalctl -u vpn-bot -n 12 --no-pager -o cat; }
