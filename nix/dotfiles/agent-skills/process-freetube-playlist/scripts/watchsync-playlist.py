#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["requests"]
# ///
"""watchsync-playlist.py — read and modify a FreeTube playlist stored on WatchSync.

Data layer for the process-freetube-playlist skill. Prints JSON for the agent.

Usage:
  watchsync-playlist.py playlists                          list every playlist (name, _id, video count)
  watchsync-playlist.py list <playlist>                    video entries of one playlist, in order
  watchsync-playlist.py remove <playlist> <playlistItemId> remove one video from the canonical playlist
  watchsync-playlist.py login --client-id ID               save the WatchSync clientId our writes are sent as

<playlist> matches a name case-insensitively, or an exact _id (e.g. watchLater).

Config: ~/.config/freetube-playlist/config.json {url, clientId}. Auth: the
SYNC_TOKEN read from FreeTube's own settings.db (watchSyncToken row), or the
WATCHSYNC_TOKEN env var if set. Base URL defaults to
https://watchsync.device.example.com, clientId to "ftproc".

Notes on removal (see WatchSync README "deletions don't propagate"):
  - Playlist records merge last-write-wins on `lastUpdatedAt`, so removal POSTs
    the playlist back minus the video with a fresh timestamp.
  - A device still holding the video can re-add it if it pushes a playlist with
    a newer lastUpdatedAt before pulling our write. The client pulls on every
    sync, so in practice this only matters when FreeTube is offline mid-run;
    re-run `remove` if the video reappears.
  - Never delete the record itself (DELETE /api/records/playlists/<id>): its
    tombstone would make the whole playlist unre-addable.

State: ~/.config/freetube-playlist/config.json (chmod 600 — it sits beside
nothing else sensitive but the clientId is all it holds).
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

import requests

DEFAULT_URL = "https://watchsync.device.example.com"
DEFAULT_CLIENT_ID = "ftproc"
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "freetube-playlist"
CONFIG = CONFIG_DIR / "config.json"
SETTINGS_DB = Path.home() / ".config/FreeTube/settings.db"


def die(msg, code=2):
    print(json.dumps({"error": msg}), file=sys.stderr)
    sys.exit(code)


def load_token():
    if os.environ.get("WATCHSYNC_TOKEN"):
        return os.environ["WATCHSYNC_TOKEN"].strip()
    try:
        for line in SETTINGS_DB.read_text().splitlines():
            if '"watchSyncToken"' in line:
                value = json.loads(line).get("value", "")
                if value:
                    return value
    except FileNotFoundError:
        pass
    die(f"no WatchSync token: set WATCHSYNC_TOKEN or sync FreeTube once (looked in {SETTINGS_DB})")


def load_config():
    cfg = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    cfg.setdefault("url", os.environ.get("WATCHSYNC_URL", DEFAULT_URL))
    cfg.setdefault("clientId", DEFAULT_CLIENT_ID)
    return cfg


def api(method, path, body=None):
    url = load_config()["url"].rstrip("/") + path
    r = requests.request(
        method, url, json=body, timeout=60,
        headers={"authorization": f"Bearer {load_token()}"},
    )
    if r.status_code == 401:
        die("watchsync rejected the token (401) — check watchSyncToken in FreeTube settings")
    if not r.ok:
        die(f"{method} {path} -> {r.status_code}: {r.text[:300]}")
    return r.json()


def fetch_playlists():
    return api("GET", "/api/sync")["collections"]["playlists"]


def find_playlist(query):
    matches = [
        p for p in fetch_playlists()
        if p.get("_id") == query or str(p.get("playlistName", "")).lower() == query.lower()
    ]
    if not matches:
        names = sorted(str(p.get("playlistName") or p.get("_id")) for p in fetch_playlists())
        die(f"no playlist named '{query}'. Playlists: {', '.join(names)}")
    if len(matches) > 1:
        die(f"'{query}' matches {len(matches)} playlists — pass the _id: {[m['_id'] for m in matches]}")
    return matches[0]


def cmd_playlists(a):
    out = [
        {"_id": p["_id"], "playlistName": p.get("playlistName"),
         "videos": len(p.get("videos") or []), "lastUpdatedAt": p.get("lastUpdatedAt")}
        for p in fetch_playlists()
    ]
    print(json.dumps(out, indent=1))


def cmd_list(a):
    pl = find_playlist(a.playlist)
    videos = [
        {"playlistItemId": v.get("playlistItemId"), "videoId": v.get("videoId"),
         "title": v.get("title"), "author": v.get("author"),
         "lengthSeconds": v.get("lengthSeconds"), "timeAdded": v.get("timeAdded"),
         "url": f"https://youtu.be/{v.get('videoId')}"}
        for v in pl.get("videos") or []
    ]
    print(json.dumps({"_id": pl["_id"], "playlistName": pl.get("playlistName"),
                      "videos": videos}, indent=1, ensure_ascii=False))


def cmd_remove(a):
    cfg = load_config()
    playlists = fetch_playlists()
    pl = next(
        (p for p in playlists
         if p["_id"] == a.playlist or str(p.get("playlistName", "")).lower() == a.playlist.lower()),
        None,
    )
    if pl is None:
        die(f"no playlist named '{a.playlist}'")
    videos = pl.get("videos") or []
    kept = [v for v in videos if v.get("playlistItemId") != a.playlistItemId]
    if len(kept) == len(videos):
        die(f"no video with playlistItemId {a.playlistItemId} in '{pl.get('playlistName')}'", code=1)
    removed = next(v for v in videos if v.get("playlistItemId") == a.playlistItemId)
    pl = {**pl, "videos": kept, "lastUpdatedAt": int(time.time() * 1000)}
    body = {
        "clientId": cfg["clientId"],
        "device": "watchsync-playlist.py",
        "collections": {"playlists": [pl]},
    }
    for attempt in range(2):
        resp = api("POST", "/api/sync", body)
        if resp.get("clientId") != cfg["clientId"]:
            # Our clientId was unknown server-side (forgotten client): this POST
            # ran as a first sync (existingWins — adds only, no replace) and a
            # fresh id was assigned. Re-send it as the id we were given: the
            # follow-up POST is then a normal second sync where our write wins.
            cfg["clientId"] = resp["clientId"]
            body["clientId"] = cfg["clientId"]
            CONFIG_DIR.mkdir(parents=True, exist_ok=True)
            CONFIG.touch(mode=0o600)
            CONFIG.chmod(0o600)
            CONFIG.write_text(json.dumps(cfg, indent=1))
            continue
        after = next(
            (p for p in resp["collections"]["playlists"] if p["_id"] == pl["_id"]), {},
        ).get("videos") or []
        still = any(v.get("playlistItemId") == a.playlistItemId for v in after)
        print(json.dumps({
            "ok": not still, "removed": removed.get("title"),
            "videoId": removed.get("videoId"), "videosAfter": len(after),
            "version": resp.get("version"), "clientId": cfg["clientId"],
            "warning": still and "video still present after push — a newer copy won the merge; retry" or None,
        }))
        return
    die("remove could not complete: server kept rejecting the clientId")


def cmd_login(a):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    cfg = load_config()
    cfg["clientId"] = a.client_id
    CONFIG.touch(mode=0o600)
    CONFIG.chmod(0o600)
    CONFIG.write_text(json.dumps(cfg, indent=1))
    print(json.dumps({"ok": True, "clientId": a.client_id, "config": str(CONFIG)}))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("playlists")
    s.set_defaults(fn=cmd_playlists)

    s = sub.add_parser("list")
    s.add_argument("playlist")
    s.set_defaults(fn=cmd_list)

    s = sub.add_parser("remove")
    s.add_argument("playlist")
    s.add_argument("playlistItemId")
    s.set_defaults(fn=cmd_remove)

    s = sub.add_parser("login")
    s.add_argument("--client-id", required=True)
    s.set_defaults(fn=cmd_login)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
