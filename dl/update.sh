#!/bin/bash
# Обновляет код бота на основном сервере (настройки .env и ключи не трогает).
#   curl -fsSL "https://hikingerop.github.io/dl/update.sh?$(date +%s)" | bash
# Код лежит на сайте зашифрованным: расшифровать его может только этот сервер своим ключом
# (/opt/vpn-bot/.update_key.pem, создаёт update-key.sh).
set -euo pipefail
cd /opt/vpn-bot
URL=https://hikingerop.github.io/dl
if [ -f .update_key.pem ]; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "$URL/merida-bot.key?$(date +%s)" -o "$TMP/key"
  curl -fsSL "$URL/merida-bot.enc?$(date +%s)" -o "$TMP/code"
  MK=$(base64 -d "$TMP/key" | openssl pkeyutl -decrypt -inkey .update_key.pem \
       -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256) \
    || { echo "❌ Не удалось расшифровать обновление этим ключом сервера"; exit 1; }
  MK="$MK" openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:MK -in "$TMP/code" | tar xz
elif curl -fsSL "$URL/merida-bot.tar.gz?$(date +%s)" -o /tmp/merida-bot.tar.gz 2>/dev/null; then
  tar xzf /tmp/merida-bot.tar.gz && rm -f /tmp/merida-bot.tar.gz
else
  echo "❌ Обновления теперь закрытые. Один раз выполните:"
  echo "   curl -fsSL \"https://hikingerop.github.io/dl/update-key.sh?\$(date +%s)\" | bash"
  echo "   и отправьте показанный ключ."
  exit 1
fi
venv/bin/pip install -q -r requirements.txt
systemctl restart vpn-bot
sleep 6
systemctl is-active vpn-bot > /dev/null && echo "✅ Бот обновлён и работает" || { echo "❌ Бот не запустился:"; journalctl -u vpn-bot -n 12 --no-pager -o cat; }
