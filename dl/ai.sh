#!/bin/bash
# Включает ИИ-поддержку (GigaChat от Сбера) на основном сервере: спрашивает ключ авторизации,
# проверяет, что GigaChat отвечает с этого сервера, вписывает ключ в .env и перезапускает бота.
#   curl -fsSL "https://hikingerop.github.io/dl/ai.sh?$(date +%s)" -o /tmp/ai.sh && bash /tmp/ai.sh
# Выключить: удалить строки GIGACHAT_ из /opt/vpn-bot/.env и systemctl restart vpn-bot
set -euo pipefail
cd /opt/vpn-bot

# серверы Сбера подписаны сертификатом Минцифры — его нет в обычном списке, кладём рядом с ботом
curl -fsSL https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt | tr -d '\r' > russian_ca.pem
cat /etc/ssl/certs/ca-certificates.crt russian_ca.pem > /tmp/giga-ca.pem

read -rsp "Вставьте «Ключ авторизации» GigaChat (его не будет видно) и нажмите Enter: " KEY < /dev/tty
echo
KEY=$(echo -n "$KEY" | tr -d ' \r\n')
[ -n "$KEY" ] || { echo "❌ Ключ пустой"; exit 1; }
# если вставили «Client ID:Client Secret» — склеиваем ключ сами
case "$KEY" in *:*) KEY=$(echo -n "$KEY" | base64 -w0);; esac

TOKEN=""
for SCOPE in GIGACHAT_API_PERS GIGACHAT_API_B2B GIGACHAT_API_CORP; do
  ANSWER=$(curl -sS -m 20 --cacert /tmp/giga-ca.pem https://ngw.devices.sberbank.ru:9443/api/v2/oauth \
    -H "Authorization: Basic $KEY" -H "RqUID: $(cat /proc/sys/kernel/random/uuid)" \
    -H "Accept: application/json" -d "scope=$SCOPE" || true)
  TOKEN=$(echo "$ANSWER" | grep -oP '"access_token"\s*:\s*"\K[^"]+' || true)
  [ -n "$TOKEN" ] && break
done
if [ -z "$TOKEN" ]; then
  echo "❌ GigaChat не принял ключ. Ответ: ${ANSWER:-нет связи с сервером Сбера}"
  echo "Проверьте, что скопирован именно «Ключ авторизации» (developers.sber.ru → проект → Настройки API)."
  exit 1
fi
echo "✅ Ключ принят (тип: $SCOPE)"

URL=""
for BASE in https://gigachat.devices.sberbank.ru/api/v1 https://api.giga.chat/v1; do
  for MODEL in GigaChat-2 GigaChat; do
    REPLY=$(curl -sS -m 40 --cacert /tmp/giga-ca.pem "$BASE/chat/completions" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Ответь одним словом: привет\"}]}" || true)
    if echo "$REPLY" | grep -q '"choices"'; then URL=$BASE; break 2; fi
  done
done
if [ -z "$URL" ]; then
  echo "❌ GigaChat не отвечает на вопросы. Последний ответ: ${REPLY:-нет связи}"
  exit 1
fi
echo "✅ GigaChat отвечает ($MODEL): $(echo "$REPLY" | grep -oP '"content"\s*:\s*"\K[^"]+' | head -1)"

sed -i '/^GIGACHAT_/d' .env
printf 'GIGACHAT_KEY=%s\nGIGACHAT_SCOPE=%s\nGIGACHAT_MODEL=%s\nGIGACHAT_URL=%s\n' "$KEY" "$SCOPE" "$MODEL" "$URL" >> .env
systemctl restart vpn-bot
sleep 6
systemctl is-active vpn-bot > /dev/null && echo "✅ ИИ-поддержка включена: напишите боту «💬 Поддержка» и задайте вопрос" \
  || { echo "❌ Бот не запустился:"; journalctl -u vpn-bot -n 12 --no-pager -o cat; }
