#!/bin/bash
# Входной сервер Merida VPN (в России): пересылает подключения на основной сервер.
#   curl -fsSL https://hikingerop.github.io/dl/relay.sh | bash
# 443 — VPN, 8443 — сервер приложения, 8080 — страница после оплаты,
# 2222 — вход в Termius на основной сервер, 2053 — его панель.
set -euo pipefail
MAIN=${1:-46.30.46.114}

echo "→ Ставлю nftables…"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nftables curl > /dev/null

echo "→ Включаю пересылку…"
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-merida-relay.conf
sysctl -q -p /etc/sysctl.d/99-merida-relay.conf

cat > /etc/merida-relay.nft <<NFT
table ip merida {}
delete table ip merida
table ip merida {
  chain prerouting {
    type nat hook prerouting priority dstnat;
    tcp dport { 443, 8443, 8080, 2053 } dnat to $MAIN
    tcp dport 2222 dnat to $MAIN:22
  }
  chain postrouting {
    type nat hook postrouting priority srcnat;
    ip daddr $MAIN masquerade
  }
}
NFT

cat > /etc/systemd/system/merida-relay.service <<UNIT
[Unit]
Description=Merida VPN relay
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/merida-relay.nft

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable -q merida-relay
systemctl restart merida-relay

if command -v ufw > /dev/null && ufw status | grep -q "Status: active"; then
  for p in 443 8443 8080 2053 2222; do ufw allow $p/tcp > /dev/null; done
  ufw route allow to $MAIN > /dev/null
fi

ME=$(curl -fsS -m 10 https://api.ipify.org || hostname -I | awk '{print $1}')
echo "--------------------------------------------"
if timeout 5 bash -c "echo > /dev/tcp/$MAIN/443" 2> /dev/null; then
  echo "✅ Основной сервер $MAIN отсюда доступен, пересылка включена."
else
  echo "❌ Основной сервер $MAIN отсюда НЕ открывается — пришлите скриншот."
fi
echo "Адрес этого сервера: $ME"
echo "Дальше: в Termius зайдите на основной сервер через $ME, порт 2222 (пароль — от основного)."
