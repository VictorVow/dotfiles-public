#!/usr/bin/env python3
"""Push the live Sidebery tree to the Firefox Desktop Tabs server, and drain
queued "close" commands to the FF Tab Closer native host.

Runs on a systemd user timer (30 s). Read side is ff-live-sidebery-tree.py
--json (sessionstore + Sidebery storage.local — the real tree: panelId,
parentId, folded, customTitle, panel names). Write side is
ff-close-tabs.py (native host -> live tab close by URL).

Skips the PUT entirely when the tree hash is unchanged — the 30 s tick then
only drains close commands.

Favicons: one icon per hostname, taken from sessionstore's own data: URIs,
PUT to /api/favicons only when new/changed (or every ICON_REFRESH, so the
server's 365d TTL never lapses). The server never fetches icons itself.

Env:
  TABS_SERVER   base URL (e.g. https://firefox-desktop-tabs.device.example.com)
  TABS_TOKEN    bearer token
  TABS_PROFILE  Firefox profile dir (default ~/.mozilla/firefox/VERTEX)
  TABS_CLOSE    path to ff-close-tabs.py (default sibling scripts/ dir)
"""
import hashlib
import time
import json
import os
import subprocess
import sys
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
SERVER = os.environ.get("TABS_SERVER", "").rstrip("/")
TOKEN = os.environ.get("TABS_TOKEN", "")
PROFILE = os.environ.get("TABS_PROFILE", str(Path.home() / ".mozilla/firefox/VERTEX"))
CLOSE = os.environ.get("TABS_CLOSE", str(HERE / "ff-close-tabs.py"))
TREE = HERE / "ff-live-sidebery-tree.py"
DEVICE = "sidebery-vertex"   # distinct from the extension's "desktop-vertex" —
                            # don't let its flat shape overwrite the real tree
HASH_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "ff-push-tree.hash"
ICONS_FILE = HASH_FILE.with_suffix(".icons.json")   # {host: [sha1, sentAt]}
ICON_REFRESH = 180 * 86400        # re-push well inside the server's 365d TTL
ICON_BATCH_BYTES = 2 * 1024 * 1024


def die(msg):
    sys.exit(f"ff-push-tree: {msg}")


def read_tree():
    out = subprocess.run(
        [sys.executable, str(TREE), "-p", PROFILE, "--json", "--icons"],
        capture_output=True, text=True)
    if out.returncode != 0:
        die(f"tree read failed: {out.stderr.strip()}")
    return json.loads(out.stdout)


def flat_and_panels(windows):
    """Flatten all windows' tabs; collect panelId -> name."""
    tabs, panels = [], {}
    for w in windows:
        for pid, p in (w.get("panels") or {}).items():
            if isinstance(p, dict) and p.get("name"):
                panels[pid] = {
                    "name": p["name"],
                    "color": p.get("color") or "toolbar",
                    "icon": p.get("iconSVG") or "icon_tabs",
                    "iconIMG": p.get("iconIMGSrc") or p.get("iconIMG") or "",
                }
        for t in w.get("tabs", []):
            title = t.get("title") or ""
            discarded = title.startswith("\U0001f4a4")
            if discarded:
                title = title[1:].lstrip()   # strip 💤 for display
            tabs.append({
                "id": t.get("id"),
                "windowId": w.get("window", 0),
                "url": t.get("url") or "",
                "title": title,
                "pinned": bool(t.get("pinned")),
                "discarded": discarded,
                "folded": bool(t.get("folded")),
                "panelId": t.get("panelId"),
                "parentId": t.get("parentId", -1),
                "color": t.get("color"),          # Sidebery customColor (may be None)
                "customTitle": None,
                "ctx": t.get("ctx") or "",
                "hidden": bool(t.get("hidden")),
            })
    # Sidebery paints descendants in a group's color; inherit nearest
    # ancestor's customColor when a tab has none of its own.
    by_id = {t["id"]: t for t in tabs}
    def inherited(t, depth=0):
        if t["color"] or depth > 50:
            return t["color"]
        p = by_id.get(t["parentId"])
        return inherited(p, depth + 1) if p else None
    for t in tabs:
        t["color"] = t["color"] or inherited(t)
    return tabs, panels


def host_icons(windows):
    """-> {hostname: data URI}. A host with several icons keeps its most
    common one (ties by value) so the pick is stable across runs."""
    seen = defaultdict(Counter)
    for w in windows:
        for t in w.get("tabs", []):
            img, u = t.get("image") or "", urlparse(t.get("url") or "")
            # UI only shows icons for http(s) tabs (not moz-extension:// etc.)
            if u.scheme in ("http", "https") and u.hostname and img.startswith("data:image/"):
                seen[u.hostname][img] += 1
    return {h: max(c, key=lambda i: (c[i], i)) for h, c in seen.items()}


def push_icons(icons):
    try:
        sent = json.loads(ICONS_FILE.read_text())
    except (OSError, ValueError):
        sent = {}
    now = time.time()
    due = {h: u for h, u in icons.items()
           if h not in sent or sent[h][0] != hashlib.sha1(u.encode()).hexdigest()
           or now - sent[h][1] > ICON_REFRESH}
    batch, size = {}, 0
    for i, (h, u) in enumerate(sorted(due.items())):
        batch[h], size = u, size + len(u)
        if size >= ICON_BATCH_BYTES or i == len(due) - 1:
            api("/api/favicons", "PUT", batch)
            # rejected ones (bad type / too big) are marked sent too, so they
            # are not retried every tick; a changed icon has a new sha anyway
            for k in batch:
                sent[k] = [hashlib.sha1(batch[k].encode()).hexdigest(), now]
            ICONS_FILE.write_text(json.dumps(sent))
            batch, size = {}, 0


def tree_hash(tabs):
    h = hashlib.sha1()
    for t in sorted(tabs, key=lambda x: (x["id"] or 0)):
        h.update(json.dumps(t, sort_keys=True).encode())
    return h.hexdigest()


def api(path, method="GET", body=None):
    req = urllib.request.Request(
        f"{SERVER}{path}",
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {TOKEN}"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read() or b"{}")


def push(tabs, panels):
    api("/api/tabs", "PUT", {
        "device": DEVICE,
        "syncedAt": __import__("datetime").datetime.now(
            __import__("datetime").timezone.utc).isoformat(),
        "panels": panels,
        "tabs": tabs,
    })


def close(mode, args):
    out = subprocess.run([sys.executable, CLOSE, mode, *args],
                         capture_output=True, text=True)
    try:
        return json.loads(out.stdout)
    except ValueError:
        return {"ok": False}


def drain(windows, tabs):
    """Run queued closes, then ack the ones that fully ran. Unacked commands
    stay queued server-side and are retried next tick (until TABS_COMMAND_TTL)."""
    res = api(f"/api/commands?device={DEVICE}")
    if res.get("hasDevice") is False:
        HASH_FILE.unlink(missing_ok=True)   # force re-PUT next cycle
        ICONS_FILE.unlink(missing_ok=True)  # server state wiped: resend icons
    urls = {t["url"] for t in tabs}
    # Sidebery id -> (tab-strip index, url) from THIS run's sessionstore read:
    # the reader keeps each window's tabs in strip order.
    pos = {t.get("id"): (i, t.get("url") or "")
           for w in windows for i, t in enumerate(w.get("tabs", []))}
    done = []
    for cmd in res.get("commands", []):
        if cmd.get("action") != "close":
            continue
        # A tab gone, or now showing another URL, is dropped: nothing to close.
        at = [f"{pos[t['id']][0]}:{t['url']}" for t in cmd.get("tabs", [])
              if t.get("id") in pos and pos[t["id"]][1] == t.get("url")]
        by_url = [u for u in cmd.get("urls", []) if u in urls]
        ok = True
        if at:
            r = close("close-at", at)
            # fewer closed = stale index (sessionstore lags ~15 s): retry next tick
            ok = r.get("ok") and len(r.get("tabs", [])) == len(at)
        if by_url:
            ok = close("close", by_url).get("ok") and ok
        if ok:
            done.append(cmd["issuedAt"])
    if done:
        api("/api/commands/ack", "POST", {"issuedAt": done})


def main():
    if not SERVER or not TOKEN:
        die("TABS_SERVER and TABS_TOKEN are required")
    windows = read_tree()
    tabs, panels = flat_and_panels(windows)
    h = tree_hash(tabs)
    prev = HASH_FILE.read_text().strip() if HASH_FILE.exists() else ""
    if h != prev:
        push(tabs, panels)
        HASH_FILE.write_text(h)
    drain(windows, tabs)
    push_icons(host_icons(windows))


if __name__ == "__main__":
    main()
