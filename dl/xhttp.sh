#!/bin/bash
# Запасное подключение Merida VPN: VLESS + XHTTP (TLS, тот же сертификат) на отдельном порту.
# Бот сам заведёт в нём всех клиентов, приложение переключится на него, если основное не отвечает.
#   curl -fsSL "https://hikingerop.github.io/dl/xhttp.sh?v=1" | bash
# Потом на входном сервере: relay.sh (пересылает и этот порт).
set -euo pipefail
PORT=${1:-2443}
cd /opt/vpn-bot

echo "→ Обновляю код бота…"
curl -fsSL "https://hikingerop.github.io/dl/merida-bot.tar.gz?$(date +%s)" | tar xz
venv/bin/pip install -q -r requirements.txt

set_env() {
  if grep -q "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else echo "$1=$2" >> .env; fi
}

if grep -qE '^FALLBACK_INBOUND_ID=[1-9]' .env; then
  echo "→ Запасное подключение уже есть — оставляю"
else
  echo "→ Создаю запасное подключение (порт $PORT)…"
  ID=$(venv/bin/python - "$PORT" <<'PY'
import asyncio, json, secrets, sys, uuid
from panel import panel

async def main():
    main_in = await panel.get_inbound()
    stream = json.loads(main_in["streamSettings"])
    if stream.get("security") != "tls":
        sys.exit("Основное подключение не на TLS — сначала tls.sh")
    tls = dict(stream["tlsSettings"], alpn=["h2", "http/1.1"])
    xhttp_stream = {
        "network": "xhttp", "security": "tls", "externalProxy": [], "tlsSettings": tls,
        "xhttpSettings": {"path": "/" + secrets.token_hex(6), "host": "", "mode": "auto", "headers": {}},
    }
    # пустой список клиентов панель может не принять — кладём выключенного «пустого»
    placeholder = {"id": str(uuid.uuid4()), "flow": "", "email": "merida-xhttp-0", "limitIp": 0, "totalGB": 0,
                   "expiryTime": 0, "enable": False, "subId": secrets.token_hex(8), "reset": 0}
    payload = {
        "up": 0, "down": 0, "total": 0, "remark": "merida-xhttp", "enable": True, "expiryTime": 0,
        "listen": "", "port": int(sys.argv[1]), "protocol": "vless",
        "settings": json.dumps({"clients": [placeholder], "decryption": "none", "fallbacks": []}),
        "streamSettings": json.dumps(xhttp_stream),
        "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]}),
    }
    res = await panel._request("POST", "/panel/api/inbounds/add", payload)
    print(res["obj"]["id"])
    await panel.close()

asyncio.run(main())
PY
)
  set_env FALLBACK_INBOUND_ID "$ID"
  echo "   номер подключения: $ID"
fi

echo "→ Добавляю в запасное подключение всех клиентов…"
venv/bin/python - <<'PY'
import asyncio, time
import config, db
from panel import panel

async def main():
    devices = db.conn.execute("SELECT * FROM devices").fetchall()
    for dev in devices:
        await panel.save_fallback(dev["email"], dev["client_uuid"], dev["expires_at"] or int(time.time()),
                                  0 if dev["paid"] else config.TRIAL_GB, reset_traffic=False)
    print(f"   клиентов: {len(devices)}")
    await panel.close()

asyncio.run(main())
PY

if command -v ufw > /dev/null && ufw status | grep -q "Status: active"; then ufw allow "$PORT/tcp" > /dev/null; fi
systemctl restart vpn-bot
sleep 6

echo
echo "== Проверка запасного подключения (сервер подключается сам к себе) =="
XRAY=$(ls /usr/local/x-ui/bin/xray-linux-* 2>/dev/null | head -1)
venv/bin/python - "$PORT" > /tmp/merida-xhttp.json <<'PY'
import json, sys, sqlite3
port = int(sys.argv[1])
db = sqlite3.connect("/etc/x-ui/x-ui.db")
row = db.execute("SELECT settings, stream_settings FROM inbounds WHERE port = ?", (port,)).fetchone()
clients = [c for c in json.loads(row[0])["clients"] if c.get("enable", True)]
stream = json.loads(row[1])
if not clients:
    sys.exit("в запасном подключении ещё нет клиентов — откройте приложение и запустите проверку снова")
print(json.dumps({
    "log": {"loglevel": "warning"},
    "inbounds": [{"listen": "127.0.0.1", "port": 10811, "protocol": "socks", "settings": {"udp": False}}],
    "outbounds": [{"protocol": "vless",
        "settings": {"vnext": [{"address": "127.0.0.1", "port": port,
                                "users": [{"id": clients[-1]["id"], "encryption": "none"}]}]},
        "streamSettings": {"network": "xhttp", "security": "tls",
            "tlsSettings": {"allowInsecure": True, "fingerprint": "chrome", "alpn": ["h2"]},
            "xhttpSettings": stream["xhttpSettings"]}}],
}))
PY
if [ -s /tmp/merida-xhttp.json ] && [ -n "$XRAY" ]; then
  "$XRAY" run -c /tmp/merida-xhttp.json > /tmp/merida-xhttp.log 2>&1 &
  PID=$!
  sleep 3
  CODE=$(curl -s -o /dev/null -m 10 -w '%{http_code}' -x socks5h://127.0.0.1:10811 https://www.google.com/generate_204)
  kill $PID 2> /dev/null || true
  if [ "$CODE" = "204" ]; then echo "ЗАПАСНОЕ ПОДКЛЮЧЕНИЕ РАБОТАЕТ ✅"; else echo "НЕ РАБОТАЕТ ❌ (код $CODE)"; tail -5 /tmp/merida-xhttp.log; fi
fi
rm -f /tmp/merida-xhttp.json
echo "Дальше: на входном сервере запустите relay.sh — он начнёт пересылать порт $PORT."
