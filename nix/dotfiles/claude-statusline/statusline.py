#!/usr/bin/env python3
# Claude Code statusline:
#   <model> | 🌡️ <effort> | ⏳ <ctx>% | 💰 $X.XX | 📁 <dir> | 🌿 <branch> | 🔗 <repo> | ⏰ N% (Xh Ym) | 📅 N% (Day HAM/PM)
# Reads session JSON from stdin (when invoked by Claude Code); when run from
# a terminal directly, falls back to defaults. Usage data cached in
# ~/.cache/claude-usage.json (15 min TTL). When the joined line exceeds the
# terminal width, parts are wrapped across multiple lines.
import json, os, re, shutil, subprocess, sys, time, urllib.request
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
CRED = HOME / ".claude" / ".credentials.json"
CACHE = HOME / ".cache" / "claude-usage.json"
TTL = 15 * 60
URL = "https://api.anthropic.com/api/oauth/usage"

payload = {}
if not sys.stdin.isatty():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        pass
model = (payload.get("model") or {}).get("display_name") \
        or (payload.get("model") or {}).get("id") or "claude"
cwd = (payload.get("workspace") or {}).get("current_dir") or os.getcwd()
dir_name = os.path.basename(cwd.rstrip("/")) or "/"
ctx_pct = int((payload.get("context_window") or {}).get("used_percentage") or 0)
cost_info = payload.get("cost") or {}
cost_usd = cost_info.get("total_cost_usd") or 0

# Live session effort is nested under effort.level in the statusline
# payload. /effort is session-only (never written to settings.json), so
# prefer the payload; only fall back to the persisted settings.json default.
effort = (payload.get("effort") or {}).get("level") \
    or payload.get("effortLevel") or payload.get("effort_level")
if not effort:
    try:
        effort = json.loads((HOME / ".claude" / "settings.json").read_text()).get("effortLevel")
    except Exception:
        effort = None

def _git(args):
    return subprocess.check_output(
        ["git", "-C", cwd] + args,
        text=True, stderr=subprocess.DEVNULL, timeout=2,
    ).strip()

branch, staged, modified = "", 0, 0
remote_url, repo_name = "", ""
try:
    _git(["rev-parse", "--git-dir"])
    branch = _git(["branch", "--show-current"])
    s = _git(["diff", "--cached", "--numstat"])
    m = _git(["diff", "--numstat"])
    staged = len(s.split("\n")) if s else 0
    modified = len(m.split("\n")) if m else 0
    try:
        remote_url = _git(["remote", "get-url", "origin"])
        remote_url = re.sub(r"^git@github\.com:", "https://github.com/", remote_url)
        remote_url = re.sub(r"\.git$", "", remote_url)
        repo_name = os.path.basename(remote_url)
    except Exception:
        remote_url, repo_name = "", ""
except Exception:
    pass

GREEN, YELLOW, RESET = "\033[32m", "\033[33m", "\033[0m"
git_extra = ""
if staged:
    git_extra += f" {GREEN}+{staged}{RESET}"
if modified:
    git_extra += f" {YELLOW}~{modified}{RESET}"

def fetch():
    token = json.loads(CRED.read_text())["claudeAiOauth"]["accessToken"]
    req = urllib.request.Request(URL, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.load(r)

data = None
try:
    st = CACHE.stat()
    if time.time() - st.st_mtime < TTL:
        data = json.loads(CACHE.read_text())
except FileNotFoundError:
    pass
except Exception:
    data = None

if data is None:
    try:
        data = fetch()
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(data))
    except Exception:
        data = {}

now = datetime.now(timezone.utc)
fh = data.get("five_hour") or {}
sd = data.get("seven_day") or {}

def reset_rel(b):
    t = b.get("resets_at")
    if not t:
        return "?"
    dt = datetime.fromisoformat(t.replace("Z", "+00:00"))
    secs = max(0, int((dt - now).total_seconds()))
    return f"{secs // 3600}h{(secs % 3600) // 60}m"

def reset_day(b):
    t = b.get("resets_at")
    if not t:
        return "?"
    dt = datetime.fromisoformat(t.replace("Z", "+00:00")).astimezone()
    return dt.strftime("%a %-I%p") if dt.minute == 0 else dt.strftime("%a %-I:%M%p")

parts = [model]
if effort:
    parts.append(f"🌡️ {effort}")
parts.append(f"⏳ {ctx_pct}%")
parts.append(f"💰 ${cost_usd:.2f}")
parts.append(f"📁 {dir_name}")
if branch:
    parts.append(f"🌿 {branch}{git_extra}")
if remote_url:
    # Wrap the link text in SGR underline (\e[4m … \e[24m) so it gets the
    # same visible "this is a link" cue as Claude Code's own PR badge
    # (PrBadge sets <Text underline={true}>). Without it, the OSC 8 region
    # is still clickable via Ctrl+Click in Konsole/Yakuake but renders
    # indistinguishably from surrounding text — users have no idea it's
    # there. Claude Code's f_ ANSI parser carries the underline prop into
    # the rendered <Link><StyledText underline …>> so both the visual cue
    # and the OSC 8 hyperlink survive the Ink round-trip.
    link = f"\033]8;;{remote_url}\033\\\033[4m{repo_name}\033[24m\033]8;;\033\\"
    parts.append(f"🔗 {link}")
if fh:
    parts.append(f"⏰ {round(fh.get('utilization', 0))}% ({reset_rel(fh)})")
else:
    parts.append("⏰ ?")
if sd:
    parts.append(f"📅 {round(sd.get('utilization', 0))}% ({reset_day(sd)})")
else:
    parts.append("📅 ?")

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m|\x1b\]8;[^\x07\x1b]*(?:\x07|\x1b\\)")

def vlen(s):
    # Visible width: strip ANSI/OSC-8 escapes, then count non-ASCII
    # (mostly emoji) as 2 cols to approximate East-Asian wide width.
    clean = ANSI_RE.sub("", s)
    return len(clean) + sum(1 for c in clean if ord(c) > 127)

# Claude Code spawns the statusline with no tty and piped stdio, so the
# only reliable width source is $COLUMNS, which Claude Code v2.1.153+
# sets before exec (anthropics/claude-code#22115, #5430). On older
# versions the wrap falls back to 120 and the host terminal clips lines.
try:
    width = int(os.environ.get("COLUMNS") or 0) \
            or shutil.get_terminal_size((120, 24)).columns
except Exception:
    width = 120

SEP = " | "
lines, cur, cur_w = [], "", 0
for p in parts:
    pw = vlen(p)
    if not cur:
        cur, cur_w = p, pw
        continue
    if cur_w + len(SEP) + pw <= width:
        cur += SEP + p
        cur_w += len(SEP) + pw
    else:
        lines.append(cur)
        cur, cur_w = p, pw
if cur:
    lines.append(cur)
print("\n".join(lines))
