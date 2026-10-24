#!/bin/bash
# 30 секунд смотрит, кто подключается к VPN (порт 443) и сколько данных проходит.
# Запуск: curl -fsSL https://hikingerop.github.io/dl/watch.sh | bash
echo "Ваш адрес в Termius: ${SSH_CLIENT%% *}"
for i in 1 2 3 4 5 6; do
  echo "-- $(date +%T)"
  ss -tnHi state established '( sport = :443 )' | awk '
    /^[0-9]/ {peer=$4}
    /bytes_received/ {r="?"; s="?"
      for (i=1;i<=NF;i++) { if ($i ~ /^bytes_received:/) r=substr($i,16); if ($i ~ /^bytes_acked:/) s=substr($i,13) }
      sub(/:[0-9]+$/, "", peer); print "  " peer "  получено " int(r/1024) " КБ, отправлено " int(s/1024) " КБ"}' | sort | uniq -c | head -12
  sleep 5
done
echo "== Готово =="
