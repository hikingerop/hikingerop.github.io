#!/bin/bash
# Обновления приложения через сервер: ставит apksigner, создаёт постоянный ключ подписи
# (он хранится только на сервере) и обновляет код бота.
#   curl -fsSL https://hikingerop.github.io/dl/release-setup.sh | bash
set -euo pipefail
cd /opt/vpn-bot

echo "→ Ставлю apksigner (подпись приложения)…"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apksigner > /dev/null

echo "→ Обновляю код бота…"
curl -fsSL https://hikingerop.github.io/dl/merida-bot.tar.gz | tar xz
venv/bin/pip install -q -r requirements.txt

if [ ! -f release.p12 ]; then
  echo "→ Создаю ключ подписи…"
  (umask 077 && openssl rand -hex 16 > release.pass)
  keytool -genkeypair -keystore release.p12 -storetype PKCS12 -alias merida \
    -keyalg EC -groupname secp256r1 -validity 10000 \
    -storepass:file release.pass -dname "CN=Merida VPN" > /dev/null 2>&1
  chmod 600 release.p12
else
  echo "→ Ключ подписи уже есть — оставляю"
fi

systemctl restart vpn-bot
sleep 6
echo "--------------------------------------------"
if systemctl is-active vpn-bot > /dev/null && [ -s release.p12 ]; then
  echo "✅ Готово: сервер принимает сборки с GitHub и подписывает их своим ключом."
  echo "SHA-1 ключа (пригодится для входа через Google):"
  keytool -list -v -keystore release.p12 -storetype PKCS12 -storepass:file release.pass | grep -m1 "SHA1:"
  echo "Сохраните копию файлов /opt/vpn-bot/release.p12 и release.pass — без них"
  echo "обновления не встанут поверх, если сервер придётся переустановить."
else
  echo "❌ Что-то не так:"
  journalctl -u vpn-bot -n 12 --no-pager -o cat
fi
