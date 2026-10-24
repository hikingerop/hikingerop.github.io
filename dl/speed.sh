#!/bin/bash
# Проверка на входном сервере: доходят ли до телефона большие данные (обычные и по TLS).
#   curl -fsSL https://hikingerop.github.io/dl/speed.sh | bash
# 10 минут отдаёт файл 2 МБ: http://IP:8081/test.bin и https://IP:8444/test.bin
mkdir -p /root/speed && cd /root/speed
head -c 2097152 /dev/urandom > test.bin
[ -f cert.pem ] || openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj /CN=test \
  -keyout key.pem -out cert.pem 2> /dev/null
pkill -f "http.server 8081" 2> /dev/null; pkill -f "s_server -accept 8444" 2> /dev/null
nohup timeout 600 python3 -m http.server 8081 > /dev/null 2>&1 &
nohup timeout 600 openssl s_server -accept 8444 -cert cert.pem -key key.pem -WWW -quiet > /dev/null 2>&1 &
sleep 1
ME=$(curl -fsS -m 10 https://api.ipify.org || hostname -I | awk '{print $1}')
echo "Готово на 10 минут. Откройте на телефоне (все VPN выключены):"
echo "  1) http://$ME:8081/test.bin"
echo "  2) https://$ME:8444/test.bin"
