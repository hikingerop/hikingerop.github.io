#!/bin/bash
# Сторож на входном сервере: раз в 2 минуты проверяет основной сервер и пишет в Telegram,
# если он перестал отвечать (и когда снова заработал). Основной сервер в ответ следит за этим.
#   curl -fsSL "https://hikingerop.github.io/dl/relay-watch.sh?v=1" | bash -s -- ТОКЕН_БОТА TELEGRAM_ID
set -euo pipefail
TOKEN="${1:?Укажите токен бота}"
ADMIN="${2:?Укажите ваш Telegram ID}"
MAIN="${3:-46.30.46.114}"

(umask 077 && printf 'TOKEN=%q\nADMIN=%q\nMAIN=%q\n' "$TOKEN" "$ADMIN" "$MAIN" > /etc/merida-watch.env)

cat > /usr/local/bin/merida-watch <<'SH'
#!/bin/bash
. /etc/merida-watch.env
STATE=/var/lib/merida-watch.state
say() { curl -s -m 20 "https://api.telegram.org/bot$TOKEN/sendMessage" -d chat_id="$ADMIN" --data-urlencode text="$1" > /dev/null; }
up() { timeout 8 bash -c "echo > /dev/tcp/$MAIN/$1" 2> /dev/null; }
# два промаха подряд — чтобы не тревожить из-за секундного сбоя
if up 443 || { sleep 20; up 443; }; then now=ok; else now=down; fi
was=$(cat "$STATE" 2> /dev/null || echo ok)
if [ "$now" != "$was" ]; then
  if [ "$now" = down ]; then
    say "⚠️ Основной сервер $MAIN не отвечает — VPN у клиентов не работает. Проверьте его в панели хостинга (включён ли, оплачен ли)."
  else
    say "✅ Основной сервер $MAIN снова отвечает."
  fi
  echo "$now" > "$STATE"
fi
SH
chmod 700 /usr/local/bin/merida-watch

cat > /etc/systemd/system/merida-watch.service <<UNIT
[Unit]
Description=Merida VPN: watch the main server
[Service]
Type=oneshot
ExecStart=/usr/local/bin/merida-watch
UNIT
cat > /etc/systemd/system/merida-watch.timer <<UNIT
[Unit]
Description=Merida VPN: watch the main server every 2 minutes
[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now merida-watch.timer > /dev/null 2>&1

if curl -s -m 20 "https://api.telegram.org/bot$TOKEN/sendMessage" -d chat_id="$ADMIN" \
    --data-urlencode text="👀 Сторож на входном сервере включён: если основной сервер перестанет отвечать, напишу сюда." | grep -q '"ok":true'; then
  echo "✅ Сторож включён — проверьте сообщение от бота в Telegram."
else
  echo "❌ Не получилось написать в Telegram — проверьте токен и Telegram ID."
fi
