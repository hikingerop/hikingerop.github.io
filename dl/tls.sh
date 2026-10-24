#!/bin/bash
# Переключает VPN-подключение Merida на обычный TLS со своим сертификатом (без маскировки под сайт).
#   curl -fsSL https://hikingerop.github.io/dl/tls.sh | bash          — включить
#   curl -fsSL https://hikingerop.github.io/dl/tls.sh | bash -s -- off — вернуть как было (Reality)
set -euo pipefail
MODE=${1:-on}
INBOUND_ID=$(grep -s '^INBOUND_ID=' /opt/vpn-bot/.env | cut -d= -f2)
cp /etc/x-ui/x-ui.db "/etc/x-ui/x-ui.db.bak-$(date +%s)"  # копия на всякий случай

echo "→ Обновляю код бота…"
cd /opt/vpn-bot
curl -fsSL https://hikingerop.github.io/dl/merida-bot.tar.gz | tar xz

x-ui stop > /dev/null
python3 - "$MODE" "${INBOUND_ID:-1}" <<'PY'
import json, os, sqlite3, sys
mode, inbound_id = sys.argv[1], int(sys.argv[2])
saved = "/etc/x-ui/stream-reality.json"
db = sqlite3.connect("/etc/x-ui/x-ui.db")
stream = json.loads(db.execute("SELECT stream_settings FROM inbounds WHERE id = ?", (inbound_id,)).fetchone()[0])
if mode == "off":
    stream = json.load(open(saved))
    print("подключение снова: Reality (маскировка под сайт)")
else:
    if stream.get("security") == "reality":
        json.dump(stream, open(saved, "w"))
    stream = {
        "network": "tcp", "security": "tls", "externalProxy": [],
        "tlsSettings": {
            "serverName": "", "minVersion": "1.2", "maxVersion": "1.3", "cipherSuites": "",
            "rejectUnknownSni": False, "alpn": ["h2", "http/1.1"],
            "certificates": [{"certificateFile": "/opt/vpn-bot/api_cert.pem",
                              "keyFile": "/opt/vpn-bot/api_key.pem", "ocspStapling": 3600}],
            "settings": {"allowInsecure": False, "fingerprint": "chrome"},
        },
        "tcpSettings": {"acceptProxyProtocol": False, "header": {"type": "none"}},
    }
    print("подключение теперь: TLS со своим сертификатом")
db.execute("UPDATE inbounds SET stream_settings = ? WHERE id = ?", (json.dumps(stream, indent=2), inbound_id))
db.commit()
PY
x-ui start > /dev/null
systemctl restart vpn-bot
sleep 5
curl -fsSL https://hikingerop.github.io/dl/check.sh | bash
