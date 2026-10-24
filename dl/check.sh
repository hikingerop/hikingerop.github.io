#!/bin/bash
# Проверка VPN на сервере Merida: работает ли Xray и подключается ли клиент по ключу.
# Запуск: curl -fsSL https://hikingerop.github.io/dl/check.sh | bash
# Ничего не меняет на сервере, пароли и ключи не показывает.

echo "== Панель и порты =="
echo "x-ui: $(systemctl is-active x-ui)   бот: $(systemctl is-active vpn-bot)"
ss -tlnp | awk 'NR>1 && $4 ~ /:(443|8443|8080|2053)$/ {print "слушает", $4}'
echo "интернет с сервера: $(curl -s -o /dev/null -m 8 -w '%{http_code}' https://www.google.com/generate_204)"

XRAY=$(ls /usr/local/x-ui/bin/xray-linux-* 2>/dev/null | head -1)
INBOUND_ID=$(grep -s '^INBOUND_ID=' /opt/vpn-bot/.env | cut -d= -f2)
HOST=$(grep -s '^SERVER_HOST=' /opt/vpn-bot/.env | cut -d= -f2)

python3 - "${INBOUND_ID:-1}" "${CHECK_HOST:-127.0.0.1}" "$XRAY" > /tmp/merida-check.json <<'PY'
import json, sqlite3, subprocess, sys, time

inbound_id, host, xray = int(sys.argv[1]), sys.argv[2], sys.argv[3]
db = sqlite3.connect("/etc/x-ui/x-ui.db")
db.row_factory = sqlite3.Row
row = db.execute("SELECT * FROM inbounds WHERE id = ?", (inbound_id,)).fetchone()
say = lambda *a: print(*a, file=sys.stderr)
say("\n== Подключение (inbound", inbound_id, ") ==")
if not row:
    say("НЕТ подключения с таким номером!")
    sys.exit(1)
settings = json.loads(row["settings"])
stream = json.loads(row["stream_settings"])
reality = stream.get("realitySettings", {})
extra = reality.get("settings", {})
say("порт:", row["port"], " включено:", bool(row["enable"]), " протокол:", row["protocol"])
say("сеть:", stream.get("network"), " защита:", stream.get("security"))
say("сайт-маскировка:", reality.get("target") or reality.get("dest"), " serverNames:", reality.get("serverNames"))
say("publicKey есть:", bool(extra.get("publicKey")), " privateKey есть:", bool(reality.get("privateKey")),
    " shortIds:", len(reality.get("shortIds") or []))
if xray and reality.get("privateKey"):
    out = subprocess.run([xray, "x25519", "-i", reality["privateKey"]], capture_output=True, text=True).stdout
    derived = next((line.split(":", 1)[1].strip() for line in out.splitlines()
                    if line.lower().startswith(("public key", "publickey", "password"))), "")
    say("пара ключей сходится:", (derived == extra.get("publicKey")) if derived else "не проверил")
try:  # что на самом деле запущено в Xray
    running = json.load(open("/usr/local/x-ui/bin/config.json"))
    live = next((i for i in running.get("inbounds", []) if i.get("port") == row["port"]), None)
    if not live:
        say("в запущенном Xray НЕТ порта", row["port"])
    else:
        live_reality = live.get("streamSettings", {}).get("realitySettings", {})
        live_ids = {c.get("id") for c in live.get("settings", {}).get("clients", [])}
        say("в запущенном Xray: клиентов", len(live_ids),
            " все из панели есть:", all(c["id"] in live_ids for c in settings.get("clients", [])),
            " ключ тот же:", live_reality.get("privateKey") == reality.get("privateKey"),
            " shortIds те же:", live_reality.get("shortIds") == reality.get("shortIds"))
except Exception as e:
    say("не прочитал запущенный конфиг:", e)

def hide(value):  # прячем ключи, остальное показываем как есть
    if isinstance(value, dict):
        return {k: ("***" if k in ("privateKey", "publicKey", "shortIds", "mldsa65Seed", "mldsa65Verify", "password")
                    else hide(v)) for k, v in value.items()}
    return [hide(v) for v in value] if isinstance(value, list) else value
say("настройки:", json.dumps(hide(stream), ensure_ascii=False))
say("listen:", repr(row["listen"]) if "listen" in row.keys() else "?")

clients = settings.get("clients", [])
apps = [c for c in clients if str(c.get("email", "")).startswith("app")]
say("клиентов:", len(clients), " из приложения:", len(apps))
client = (apps or clients or [None])[-1]
if not client:
    say("Клиентов нет — проверить нечего")
    sys.exit(1)
traffic = db.execute("SELECT * FROM client_traffics WHERE email = ?", (client["email"],)).fetchone()
say("последний клиент:", client["email"], " flow:", client.get("flow") or "-", " включён:", client.get("enable"))
if traffic:
    left = (traffic["expiry_time"] / 1000 - time.time()) / 86400 if traffic["expiry_time"] else None
    say("  в статистике включён:", bool(traffic["enable"]),
        " потрачено МБ:", round((traffic["up"] + traffic["down"]) / 2**20, 1),
        " дней осталось:", round(left, 1) if left is not None else "без срока")
for row_t in db.execute("SELECT email, up, down FROM client_traffics ORDER BY email"):
    say("  трафик", row_t["email"], ": отправлено КБ", row_t["up"] // 1024, " получено КБ", row_t["down"] // 1024)

print(json.dumps({
    "log": {"loglevel": "debug"},
    "inbounds": [{"listen": "127.0.0.1", "port": 10808, "protocol": "socks", "settings": {"udp": False}}],
    "outbounds": [{
        "protocol": "vless",
        "settings": {"vnext": [{"address": host, "port": row["port"], "users": [
            {"id": client["id"], "encryption": "none", "flow": client.get("flow", "")}]}]},
        "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {
            "serverName": (reality.get("serverNames") or [""])[0],
            "fingerprint": extra.get("fingerprint") or "chrome",
            "publicKey": extra.get("publicKey", ""),
            "shortId": (reality.get("shortIds") or [""])[0],
            "spiderX": "/"}},
    }],
}))
PY

echo
echo "== Проверка ключа (подключение через ${CHECK_HOST:-127.0.0.1}) =="
if [ ! -s /tmp/merida-check.json ] || [ -z "$XRAY" ]; then
  echo "не получилось собрать проверку"
else
  "$XRAY" run -c /tmp/merida-check.json > /tmp/merida-check.log 2>&1 &
  PID=$!
  sleep 3
  CODE=$(curl -s -o /dev/null -m 10 -w '%{http_code}' -x socks5h://127.0.0.1:10808 https://www.google.com/generate_204)
  kill $PID 2> /dev/null
  if [ "$CODE" = "204" ]; then echo "КЛЮЧ РАБОТАЕТ ✅"; else echo "КЛЮЧ НЕ РАБОТАЕТ ❌ (код $CODE)"; grep -vE "accepted|Reading config|A unified|Penetrates" /tmp/merida-check.log | tail -8; fi
fi
rm -f /tmp/merida-check.json

echo
echo "== Маскировка =="
echo "кто на 443: $(ss -tlnp | awk '$4 ~ /:443$/ {print $6}')"
echo "microsoft с сервера: $(curl -s -o /dev/null -m 8 -w '%{http_code}' https://www.microsoft.com)  по IPv6: $(curl -6 -s -o /dev/null -m 5 -w '%{http_code}' https://www.microsoft.com)"
echo "TLS через 443: $(timeout 8 openssl s_client -connect 127.0.0.1:443 -servername www.microsoft.com < /dev/null 2>&1 | grep -m1 -E 'subject=|errno|refused|alert' || echo 'сертификата нет')"
echo "IPv6 на сервере: $(ip -6 route show default 2> /dev/null | head -1)$( [ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2> /dev/null)" = 1 ] && echo выключен)"
for f in /usr/local/x-ui/*.log /usr/local/x-ui/bin/*.log; do [ -s "$f" ] && echo "-- $f" && tail -4 "$f"; done

echo
echo "== Ошибки Xray =="
journalctl -u x-ui --since "-10min" --no-pager 2> /dev/null | grep -iE "error|fail|rejected|invalid|reality" | tail -6
echo "== Готово =="
