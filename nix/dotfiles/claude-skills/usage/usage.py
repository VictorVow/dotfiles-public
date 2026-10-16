#!/usr/bin/env python3
import json, sys, urllib.request
from datetime import datetime, timezone
from pathlib import Path

CRED = Path.home() / ".claude" / ".credentials.json"
URL = "https://api.anthropic.com/api/oauth/usage"

try:
    token = json.loads(CRED.read_text())["claudeAiOauth"]["accessToken"]
except Exception as e:
    sys.exit(f"failed to read OAuth token from {CRED}: {e}")

req = urllib.request.Request(URL, headers={"Authorization": f"Bearer {token}"})
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.load(r)
except Exception as e:
    sys.exit(f"request failed: {e}")

now = datetime.now(timezone.utc)

def pct(b):
    return f"{round(b['utilization'])}% used" if b else "n/a"

def rel(b):
    if not b or not b.get("resets_at"):
        return ""
    t = datetime.fromisoformat(b["resets_at"].replace("Z", "+00:00"))
    secs = max(0, int((t - now).total_seconds()))
    h, m = secs // 3600, (secs % 3600) // 60
    return f"resets in {h}h {m}m"

def absfmt(b):
    if not b or not b.get("resets_at"):
        return ""
    t = datetime.fromisoformat(b["resets_at"].replace("Z", "+00:00")).astimezone()
    return f"resets {t.strftime('%a %-I:%M %p')}"

fh = data.get("five_hour")
sd = data.get("seven_day")
so = data.get("seven_day_sonnet")

print(f"Current session: {pct(fh)} ({rel(fh)})")
print(f"All models: {pct(sd)} ({absfmt(sd)})")
print(f"Sonnet only: {pct(so)} ({absfmt(so)})")
