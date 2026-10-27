#!/bin/bash
# Скачивает код бота с сайта и расшифровывает его в /opt/vpn-bot ключом этого сервера
# (/opt/vpn-bot/.update_key.pem, создаёт update-key.sh). Вызывают update.sh, install.sh и другие скрипты.
set -euo pipefail
DIR=/opt/vpn-bot
URL=https://hikingerop.github.io/dl
if [ ! -f "$DIR/.update_key.pem" ]; then
  echo "❌ На сервере нет ключа обновлений. Один раз выполните:"
  echo "   curl -fsSL \"$URL/update-key.sh?\$(date +%s)\" | bash"
  echo "   и отправьте показанный ключ — под него зашифруют код бота."
  exit 1
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$URL/merida-bot.key?$(date +%s)" -o "$TMP/key"
curl -fsSL "$URL/merida-bot.enc?$(date +%s)" -o "$TMP/code"
MK=$(base64 -d "$TMP/key" | openssl pkeyutl -decrypt -inkey "$DIR/.update_key.pem" \
     -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 2>/dev/null) \
  || { echo "❌ Обновление зашифровано не под ключ этого сервера — отправьте ключ из update-key.sh"; exit 1; }
MK="$MK" openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:MK -in "$TMP/code" | tar xz -C "$DIR"
