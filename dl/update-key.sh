#!/bin/bash
# Один раз на основном сервере: создаёт ключ для закрытых обновлений бота и показывает его открытую часть.
# Закрытая часть (/opt/vpn-bot/.update_key.pem) остаётся только на сервере; открытую можно отправить кому угодно —
# ею код только шифруют, расшифровать им нельзя.
#   curl -fsSL "https://hikingerop.github.io/dl/update-key.sh?$(date +%s)" | bash
set -euo pipefail
KEY=/opt/vpn-bot/.update_key.pem
if [ ! -f "$KEY" ]; then
  (umask 077; openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$KEY" 2>/dev/null)
fi
chmod 600 "$KEY"
echo "✅ Ключ обновлений на месте. Скопируйте всё ниже, вместе со строками BEGIN и END, и отправьте:"
echo
openssl pkey -in "$KEY" -pubout
