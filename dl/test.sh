#!/bin/bash
# Пробный запуск VPN на сервере Merida в отдельной копии Xray (порт 14443, только для этого сервера).
# Перебирает сайты-маскировки и показывает, какой работает. Рабочий VPN не трогает.
# Запуск: curl -fsSL https://hikingerop.github.io/dl/test.sh | bash

XRAY=$(ls /usr/local/x-ui/bin/xray-linux-* 2>/dev/null | head -1)
INBOUND_ID=$(grep -s '^INBOUND_ID=' /opt/vpn-bot/.env | cut -d= -f2)

python3 - "$XRAY" "${INBOUND_ID:-1}" <<'PY'
import json, os, sqlite3, subprocess, sys, tempfile, time

xray, inbound_id = sys.argv[1], int(sys.argv[2])
row = sqlite3.connect("/etc/x-ui/x-ui.db").execute(
    "SELECT settings, stream_settings FROM inbounds WHERE id = ?", (inbound_id,)).fetchone()
clients = json.loads(row[0])["clients"]
reality = json.loads(row[1])["realitySettings"]
client = ([c for c in clients if str(c.get("email", "")).startswith("app")] or clients)[-1]
public_key = reality["settings"]["publicKey"]
short_id = reality["shortIds"][0]
work = tempfile.mkdtemp()


def attempt(site: str, fingerprint: str) -> tuple[bool, str, str]:
    server = {
        "log": {"loglevel": "debug"},
        "inbounds": [{
            "listen": "127.0.0.1", "port": 14443, "protocol": "vless",
            "settings": {"clients": [{"id": client["id"], "flow": client.get("flow", "")}], "decryption": "none"},
            "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {
                "dest": f"{site}:443", "serverNames": [site],
                "privateKey": reality["privateKey"], "shortIds": reality["shortIds"]}},
        }],
        "outbounds": [{"protocol": "freedom"}],
    }
    user = {
        "log": {"loglevel": "debug"},
        "inbounds": [{"listen": "127.0.0.1", "port": 10809, "protocol": "socks", "settings": {"udp": False}}],
        "outbounds": [{
            "protocol": "vless",
            "settings": {"vnext": [{"address": "127.0.0.1", "port": 14443, "users": [
                {"id": client["id"], "encryption": "none", "flow": client.get("flow", "")}]}]},
            "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {
                "serverName": site, "fingerprint": fingerprint, "publicKey": public_key,
                "shortId": short_id, "spiderX": "/"}},
        }],
    }
    procs = []
    for name, conf in (("server", server), ("user", user)):
        path = os.path.join(work, name + ".json")
        with open(path, "w") as f:
            json.dump(conf, f)
        procs.append(subprocess.Popen([xray, "run", "-c", path], stdout=open(path + ".log", "w"),
                                      stderr=subprocess.STDOUT))
    time.sleep(2)
    code = subprocess.run(["curl", "-s", "-o", "/dev/null", "-m", "10", "-w", "%{http_code}",
                           "-x", "socks5h://127.0.0.1:10809", "https://www.google.com/generate_204"],
                          capture_output=True, text=True).stdout
    for p in procs:
        p.kill()
        p.wait()
    logs = []
    for name in ("server", "user"):
        lines = open(os.path.join(work, name + ".json.log")).read().splitlines()
        keep = [l.split("] ", 2)[-1] for l in lines
                if any(w in l.lower() for w in ("reality", "fail", "error", "invalid", "eof", "rejected"))]
        logs.append("\n    ".join(keep[-4:]) or "-")
    return code == "204", logs[0], logs[1]


print("Xray:", subprocess.run([xray, "version"], capture_output=True, text=True).stdout.splitlines()[0])
first = True
for site, fingerprint in (("www.microsoft.com", "chrome"), ("www.microsoft.com", "firefox"),
                          ("dl.google.com", "chrome"), ("www.apple.com", "chrome"),
                          ("www.samsung.com", "chrome")):
    ok, server_log, user_log = attempt(site, fingerprint)
    print(f"{'✅' if ok else '❌'} {site} / {fingerprint}")
    if not ok and first:
        print("  сервер:\n    " + server_log)
        print("  клиент:\n    " + user_log)
        first = False
os.system(f"rm -rf {work}")
PY
echo "== Готово =="
