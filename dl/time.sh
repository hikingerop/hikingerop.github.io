#!/bin/bash
# Проверяет часы сервера по точному времени (Google) и, если они сбились, ставит точное время
# и включает автосинхронизацию. Пароли и настройки бота не трогает.
#   curl -fsSL "https://hikingerop.github.io/dl/time.sh?$(date +%s)" | bash
REAL=$(curl -sI -m 10 https://www.google.com | awk -F': ' 'tolower($1)=="date" {print $2}' | tr -d '\r')
[ -z "$REAL" ] && { echo "❌ Не получилось узнать точное время"; exit 1; }
DIFF=$(( $(date +%s) - $(date -d "$REAL" +%s) ))
echo "Точное время (Москва): $(TZ=Europe/Moscow date -d "$REAL" '+%d.%m %H:%M:%S')"
echo "Часы сервера (Москва): $(TZ=Europe/Moscow date '+%d.%m %H:%M:%S')   расхождение: ${DIFF} сек"
echo "Часовой пояс Москвы у бота: $(/opt/vpn-bot/venv/bin/python -c 'import datetime,zoneinfo; print(datetime.datetime.now(zoneinfo.ZoneInfo("Europe/Moscow")).strftime("%H:%M (UTC%z)"))')"
if [ "${DIFF#-}" -gt 60 ]; then
  echo "→ Часы сбились — ставлю точное время"
  date -s "$REAL" > /dev/null
fi
if ! timedatectl show -p NTPSynchronized --value 2> /dev/null | grep -q yes; then
  echo "→ Включаю автосинхронизацию часов"
  apt-get install -y -qq systemd-timesyncd > /dev/null 2>&1
  timedatectl set-ntp true 2> /dev/null
fi
apt-get install -y -qq --only-upgrade tzdata > /dev/null 2>&1
echo "Сейчас на сервере (Москва): $(TZ=Europe/Moscow date '+%d.%m %H:%M:%S')"
systemctl restart vpn-bot && echo "✅ Готово, бот перезапущен"
