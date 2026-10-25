#!/bin/bash
# Подключает оплату ЮKassa: shopId и секретный ключ из кабинета ЮKassa (Интеграция → Ключи API).
# Ключ вставляется по запросу и на экран не выводится.
#   curl -fsSL "https://hikingerop.github.io/dl/pay.sh?$(date +%s)" | bash
set -euo pipefail
cd /opt/vpn-bot
SHOP="${1:-}"
KEY="${2:-}"
[ -z "$SHOP" ] && read -rp "shopId (только цифры): " SHOP < /dev/tty
[ -z "$KEY" ] && { read -rsp "Секретный ключ (live_… — при вставке не виден, это нормально): " KEY < /dev/tty; echo; }
SHOP=$(echo "$SHOP" | tr -d ' \r\n')
KEY=$(echo "$KEY" | tr -d ' \r\n')
[[ "$SHOP" =~ ^[0-9]+$ ]] || { echo "❌ shopId — это только цифры"; exit 1; }
[[ "$KEY" =~ ^(live|test)_[A-Za-z0-9_-]+$ ]] || { echo "❌ Секретный ключ начинается с live_ или test_"; exit 1; }

echo "→ Проверяю ключ в ЮKassa…"
ME=$(curl -sS -m 20 -u "$SHOP:$KEY" https://api.yookassa.ru/v3/me) || { echo "❌ ЮKassa не отвечает"; exit 1; }
echo "$ME" | python3 -c '
import json, sys
me = json.load(sys.stdin)
if me.get("type") == "error":
    print("❌ ЮKassa не приняла ключ:", me.get("description") or me.get("code")); sys.exit(1)
print("   магазин:", me.get("account_id"), " статус:", me.get("status"), " тестовый:", "да" if me.get("test") else "нет")
methods = ", ".join(me.get("payment_methods") or [])
if methods: print("   способы оплаты:", methods)
' || exit 1

set_env() {
  if grep -q "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else echo "$1=$2" >> .env; fi
}
set_env YOOKASSA_SHOP_ID "$SHOP"
set_env YOOKASSA_SECRET_KEY "$KEY"
systemctl restart vpn-bot
sleep 6
if systemctl is-active vpn-bot > /dev/null; then
  echo "✅ Оплата подключена. Проверь: в боте «Купить подписку» → номер аккаунта → должна открыться страница ЮKassa."
else
  echo "❌ Бот не запустился:"; journalctl -u vpn-bot -n 12 --no-pager -o cat
fi
