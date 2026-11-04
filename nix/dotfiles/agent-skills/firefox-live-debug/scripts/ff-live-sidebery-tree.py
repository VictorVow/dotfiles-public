#!/usr/bin/env python3
"""Print the live Sidebery tab tree of a Firefox profile.

Reads sessionstore-backups/recovery.jsonlz4 (rewritten by Firefox every ~15 s —
no restart needed, safe while it runs). Each sessionstore tab carries Sidebery's
own extData blob (extension {3c078156-…}:data) with panelId/parentId/folded/id,
and sessionstore provides title, URL, userContextId (container). Panels and
containers come from Sidebery's storage.local via the same decoder as
ff-ext-storage.py.

Output: indented Markdown — one heading per window, per panel, then the tab
tree (parentId → nesting) as "[title](url)" list items, like Sidebery's own
.md snapshots. Markers: 📌 pinned section first; "▸ title" = folded Sidebery
group (a group.html parent tab); a "💤 " already inside a stored title means
the tab is discarded/unloaded; a non-default container is appended in
brackets.

Usage: ff-live-sidebery-tree.py [-p PROFILE_DIR] [FILTER] [--json [--icons]]
--icons adds each tab's sessionstore favicon (`image`, usually a data: URI;
~10 MB across 2000 tabs) to the JSON nodes.
FILTER is a substring matched against title+URL (case-insensitive); matching
tabs keep their parent chain so the tree context survives.
"""
import argparse
import importlib.util
import json
import signal
import sqlite3
import sys
import tempfile
from pathlib import Path

_here = Path(__file__).resolve().parent


def _load(name, file):
    spec = importlib.util.spec_from_file_location(name, _here / file)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


_stats = _load("ff_session_stats", "ff-session-stats.py")   # pure-Python mozLz4
ffes = _load("ff_ext_storage", "ff-ext-storage.py")          # storage.local decoder

# Sessionstore extData key — set in main() from the active Sidebery's addon id
# (a custom Sidebery build has a different id than the upstream addon).
SIDEBERY_EXTDATA = ""


def resolve_sidebery(profile_dir: Path):
    """-> (addon id, internal uuid) of the ACTIVE Sidebery extension.

    Matches by name, then by `active`: a custom build can be installed
    alongside upstream Sidebery, but only one is enabled at a time."""
    addons = json.loads((profile_dir / "extensions.json").read_text()).get("addons", [])
    hits = [a["id"] for a in addons if a.get("active") and "sidebery" in
            ((a.get("defaultLocale") or {}).get("name") or "").lower()]
    if len(hits) != 1:
        sys.exit(f"error: expected exactly one active Sidebery (matched: {len(hits)})")
    _, addon_id, uuid = ffes.resolve_extension(profile_dir, hits[0])
    return addon_id, uuid


def load_session(profile_dir: Path) -> dict:
    for p in (profile_dir / "sessionstore.jsonlz4",
              profile_dir / "sessionstore-backups" / "recovery.jsonlz4",
              profile_dir / "sessionstore-backups" / "previous.jsonlz4"):
        if p.exists():
            return _stats.load_jsonlz4(p)
    sys.exit(f"error: no sessionstore jsonlz4 found under {profile_dir}")


def sidebery_storage(profile_dir: Path, uuid: str) -> dict:
    """-> {'sidebar': {...}, 'containers': {...}} from Sidebery storage.local"""
    out = {}
    with tempfile.TemporaryDirectory() as tmp:
        for label, db in ffes.copy_dbs(profile_dir, uuid, Path(tmp)):
            if label != "storage.local":
                continue
            con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            for k, data, fids in con.execute(
                    "select key, data, file_ids from object_data"):
                key = ffes.decode_key(k)
                if key in ("sidebar", "containers") and key not in out:
                    out[key] = ffes.read_value(db, data, fids)
    return out


def _sidebery_data(tab: dict) -> dict:
    raw = (tab.get("extData") or {}).get(SIDEBERY_EXTDATA)
    try:
        return json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        return {}


def ctx_name(containers: dict, user_ctx_id) -> str:
    if user_ctx_id in (0, 1, None):
        return ""
    cid = f"firefox-container-{user_ctx_id}"
    c = containers.get(cid) or {}
    return f" [{c.get('name', cid)}]"


def tab_node(t: dict, containers: dict) -> dict:
    entries = t.get("entries") or [{}]
    ent = entries[min(t.get("index", len(entries)), len(entries)) - 1]
    sd = _sidebery_data(t)
    title = sd.get("customTitle") or ent.get("title") or ent.get("url") or "?"
    return {
        "id": sd.get("id"), "title": title,
        "url": ent.get("url") or "",
        "pinned": bool(t.get("pinned") or sd.get("pin")),
        "folded": bool(sd.get("folded")),
        "panelId": sd.get("panelId"),
        "parentId": sd.get("parentId", -1),
        "color": sd.get("customColor"),
        "ctx": ctx_name(containers, t.get("userContextId")),
        "hidden": bool(t.get("hidden")),
    }


def _line(n, depth):
    mark = "▸ " if n["folded"] else ""
    return "  " * depth + f"- {mark}[{n['title']}]({n['url']}){n['ctx']}"


def render(win_idx: int, tabs: list, panels: dict, containers: dict,
           win_title: str = ""):
    nodes = [tab_node(t, containers) for t in tabs]
    nodes.sort(key=lambda n: (n["id"] is None, n["id"] or 0))
    pinned = [n for n in nodes if n["pinned"]]
    by_panel = {}
    for n in nodes:
        if not n["pinned"]:
            by_panel.setdefault(n["panelId"], []).append(n)

    lines = [f"# Sidebery window {win_idx}" + (f" — {win_title}" if win_title else "")]
    if pinned:
        lines.append("\n- ## 📌 Pinned")
        for n in pinned:
            lines.append("  " + _line(n, 0).lstrip())

    kids = {}
    for n in nodes:
        if n["parentId"] not in (None, -1):
            kids.setdefault(n["parentId"], []).append(n)

    def emit(node_list, depth):
        for n in node_list:
            if n["parentId"] in (None, -1):
                lines.append(_line(n, depth))
                emit_children(n["id"], depth + 1)

    def emit_children(pid, depth):
        for c in kids.get(pid, []):
            lines.append(_line(c, depth))
            emit_children(c["id"], depth + 1)

    ordered = [p for p in panels.values()
               if isinstance(p, dict) and p.get("type") == 2]
    seen = set()
    for p in ordered:
        tl = by_panel.get(p["id"])
        if not tl:
            continue
        seen.add(p["id"])
        lines.append(f"\n- ## {p.get('name', p['id'])} ({len(tl)})")
        emit(tl, 1)
    for pid, tl in by_panel.items():
        if pid not in seen:
            lines.append(f"\n- ## (panel {pid}) ({len(tl)})")
            emit(tl, 1)
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-p", "--profile", type=Path,
                    default=Path.home() / ".mozilla/firefox/VERTEX")
    ap.add_argument("--json", action="store_true",
                    help="emit raw JSON instead of Markdown")
    ap.add_argument("--icons", action="store_true",
                    help="with --json: include each tab's favicon (image)")
    ap.add_argument("filter", nargs="?", default="")
    args = ap.parse_args()
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

    profile_dir = args.profile
    if not profile_dir.is_dir():
        sys.exit(f"error: profile dir not found: {profile_dir}")

    global SIDEBERY_EXTDATA
    addon_id, uuid = resolve_sidebery(profile_dir)
    SIDEBERY_EXTDATA = f"extension:{addon_id}:data"

    ss = load_session(profile_dir)
    st = sidebery_storage(profile_dir, uuid)
    panels = (st.get("sidebar") or {}).get("panels") or {}
    containers = st.get("containers") or {}

    if args.json:
        out = []
        for i, w in enumerate(ss.get("windows", [])):
            out.append({"window": i, "title": w.get("title") or "",
                        "panels": panels,
                        "tabs": [dict(tab_node(t, containers),
                                      **({"image": t.get("image")} if args.icons else {}))
                                 for t in w.get("tabs", [])]})
        print(json.dumps(out, indent=1, ensure_ascii=False))
        return

    q = args.filter.lower()
    for i, w in enumerate(ss.get("windows", [])):
        tabs = w.get("tabs", [])
        if q:
            by_id = {}
            for t in tabs:
                sid = _sidebery_data(t).get("id")
                if sid is not None:
                    by_id[sid] = t
            keep = set()
            for t in tabs:
                blob = json.dumps(t, ensure_ascii=False).lower()
                if q in blob:
                    cur = t
                    while cur is not None:
                        sid = _sidebery_data(cur).get("id")
                        if sid in keep:
                            break
                        keep.add(sid)
                        cur = by_id.get(_sidebery_data(cur).get("parentId"))
            tabs = [t for t in tabs if _sidebery_data(t).get("id") in keep]
            if not tabs:
                continue
        for line in render(i, tabs, panels, containers, w.get("title") or ""):
            print(line)


if __name__ == "__main__":
    main()
