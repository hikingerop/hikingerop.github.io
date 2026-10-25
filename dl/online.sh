#!/bin/bash
# Кто сейчас в VPN: что видит панель 3x-ui и что записано у бота. Ничего не меняет.
#   curl -fsSL "https://hikingerop.github.io/dl/online.sh?$(date +%s)" | bash
cd /opt/vpn-bot
venv/bin/python - <<'PY'
import asyncio, time
from datetime import datetime
import db
from panel import panel

async def main():
    now = int(time.time())
    online = await panel.onlines()
    stats = await panel.client_stats()
    print("Панель видит онлайн:", ", ".join(sorted(online)) or "никого")
    print()
    for d in db.list_devices(0, 50):
        emails = [d["email"], panel.fallback_email(d["email"])]
        traffic = sum((stats.get(e) or {}).get("up", 0) + (stats.get(e) or {}).get("down", 0) for e in emails)
        last = max(int((stats.get(e) or {}).get("lastOnline") or 0) // 1000 for e in emails)
        seen = d["last_seen"]
        print(db.format_code(db.ensure_code(d["device_id"])), d["email"],
              "| онлайн:", "ДА" if set(emails) & online else "нет",
              "| трафик МБ:", round(traffic / 2**20, 1),
              "| панель lastOnline:", datetime.fromtimestamp(last).strftime("%d.%m %H:%M") if last else "-",
              "| бот last_seen:", datetime.fromtimestamp(seen).strftime("%d.%m %H:%M") if seen else "-")
    await panel.close()
asyncio.run(main())
PY
echo
journalctl -u vpn-bot --since "-30min" --no-pager -o cat | grep -iE "активност|error|traceback" | tail -5
