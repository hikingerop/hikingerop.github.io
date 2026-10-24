#!/bin/bash
# Меняет сайт-маскировку у VPN-подключения Merida. Пример:
#   curl -fsSL https://hikingerop.github.io/dl/target.sh | bash -s -- www.samsung.com
SITE=${1:-www.samsung.com}
INBOUND_ID=$(grep -s '^INBOUND_ID=' /opt/vpn-bot/.env | cut -d= -f2)
cp /etc/x-ui/x-ui.db /etc/x-ui/x-ui.db.bak  # копия на всякий случай
x-ui stop > /dev/null
python3 - "$SITE" "${INBOUND_ID:-1}" <<'PY'
import json, sqlite3, sys
site, inbound_id = sys.argv[1], int(sys.argv[2])
db = sqlite3.connect("/etc/x-ui/x-ui.db")
stream = json.loads(db.execute("SELECT stream_settings FROM inbounds WHERE id = ?", (inbound_id,)).fetchone()[0])
reality = stream["realitySettings"]
for key in ("dest", "target"):
    if key in reality or key == "dest" and "target" not in reality:
        reality[key] = f"{site}:443"
reality["serverNames"] = [site]
db.execute("UPDATE inbounds SET stream_settings = ? WHERE id = ?", (json.dumps(stream, indent=2), inbound_id))
db.commit()
print("сайт-маскировка теперь:", site)
PY
x-ui start > /dev/null
sleep 4
curl -fsSL https://hikingerop.github.io/dl/check.sh | bash
