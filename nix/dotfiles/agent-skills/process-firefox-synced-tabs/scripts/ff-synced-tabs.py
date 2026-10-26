#!/usr/bin/env python3
# Extract synced-tabs data from a Firefox profile's synced-tabs.db — the same
# source about:firefoxview renders — without needing remote debugging.
#
# Usage:
#   ff-synced-tabs.py [--profile VERTEX] [--device GUID-PREFIX ... | --all-devices]
#                     [--skip-urls FILE] [--out queue.json] [--scratch DIR]
#
# Prints a per-device summary (name, guid, sync age, tab counts, cross-device
# URL overlap) and writes a resumable queue JSON the skill then processes.
# Reading is side-effect free; nothing here dismisses rows.
import json, os, re, shutil, sqlite3, sys, tempfile
from urllib.parse import urlparse, parse_qs, unquote_plus

FF_BASE = os.environ.get("FF_BASE", os.path.expanduser("~/.mozilla/firefox"))

def copy_db(profile_dir, scratch):
    src = os.path.join(profile_dir, "synced-tabs.db")
    dst = os.path.join(scratch, "synced-tabs.db")
    if not os.path.exists(src):
        sys.exit(f"error: {src} not found (no synced tabs?)")
    for ext in ("", "-wal", "-shm"):
        if os.path.exists(src + ext):
            shutil.copy(src + ext, dst + ext)
    return dst

# suffixes that identify the site, not the page — strip " - X"/" | X" tails
_SITE_TAILS = re.compile(
    r"\s*(?:\||-|·|—|–)\s*(?:"
    r"GitHub|GitLab|Brave Search|Google Search|Hacker News|YouTube|"
    r"Reddit|Wikipedia|Stack Overflow|Stack Exchange|Amazon|Medium|"
    r"PCGamingWiki PCGW|Nexus [Mm]ods|Royal Road|BBC|Reuters|"
    r"AlternativeTo|Product Hunt|Wikibooks|DevDocs|MDN Web Docs"
    r")[^-|·—–]*$")

def linktext(title, url):
    """Title for the markdown link, cleaned per logseq-add-md-to-blocks rules."""
    t = (title or "").strip()
    if " | " in t:
        t = t.rsplit(" | ", 1)[0].strip()
    if t.startswith("GitHub - "):
        t = t[len("GitHub - "):]
    prev = None
    while prev != t:
        prev = t
        t = _SITE_TAILS.sub("", t).strip()
    p = urlparse(url)
    if not t:
        for key in ("q", "query", "text", "search"):
            qs = parse_qs(p.query)
            if key in qs and qs[key][0]:
                t = unquote_plus(qs[key][0]); break
        if not t:
            t = p.netloc + (p.path[:40] if p.path != "/" else "")
    # amazon search links: use the k= param
    if "amazon." in p.netloc and p.path in ("/s", "/gp/search"):
        k = parse_qs(p.query).get("k")
        if k: t = "Amazon: " + unquote_plus(k[0])
    t = t.replace("#", "\\#")
    if t.startswith("[["): t = t[2:]
    t = t.replace("]", ")")
    return t

def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", default="VERTEX")
    ap.add_argument("--device", action="append", default=[],
                    help="guid prefix of device(s) to include; repeatable")
    ap.add_argument("--all-devices", action="store_true",
                    help="process every device record (default: only the most "
                         "recently synced record whose name contains 'fennec'; "
                         "falls back to the newest record if none matches)")
    ap.add_argument("--skip-urls", help="file of URLs (one per line) to exclude")
    ap.add_argument("--out", default=None, help="queue path (default <scratch>/queue.json)")
    ap.add_argument("--scratch", default="/tmp/ff-synced-tabs")
    args = ap.parse_args()

    profile_dir = os.path.join(FF_BASE, args.profile)
    if not os.path.isdir(profile_dir):
        sys.exit(f"error: profile dir not found: {profile_dir}")
    os.makedirs(args.scratch, exist_ok=True)
    db = copy_db(profile_dir, args.scratch)

    con = sqlite3.connect(db)
    # sanity: schema is what we expect (table + a JSON record per device)
    cols = {r[1] for r in con.execute("PRAGMA table_info(tabs)")}
    if not {"guid", "record", "last_modified"} <= cols:
        sys.exit(f"error: tabs schema changed (cols={sorted(cols)}); "
                 "update ff-synced-tabs.py for the new layout")
    devices = []
    for guid, rec, lm in con.execute("SELECT guid, record, last_modified FROM tabs"):
        try:
            r = json.loads(rec)
        except json.JSONDecodeError:
            sys.exit(f"error: record for {guid[:8]} isn't JSON "
                     f"(starts {rec[:60]!r}) — schema changed?")
        tabs = []
        for t in r.get("tabs", []):
            url = (t.get("urlHistory") or [""])[0]
            if not url:
                continue
            tabs.append({"title": t.get("title", ""), "url": url,
                         "lastUsed": t.get("lastUsed", 0)})
        devices.append({
            "guid": guid, "name": r.get("clientName") or guid,
            "last_modified": lm, "tabs": tabs,
        })
    con.close()

    if not devices:
        sys.exit("error: 0 device records in synced-tabs.db — "
                 "is Sync signed in? Has the layout changed?")

    # summary: per-device + pairwise URL overlap
    print(f"{len(devices)} device records")
    import datetime
    urlsets = {d["guid"]: {(t["url"]) for t in d["tabs"]} for d in devices}
    for d in devices:
        lm = datetime.datetime.fromtimestamp(d["last_modified"] / 1000)
        used = [t["lastUsed"] for t in d["tabs"] if t["lastUsed"]]
        newest = datetime.datetime.fromtimestamp(max(used)) if used else "-"
        print(f"  {d['name']} [{d['guid'][:8]}]  tabs={len(d['tabs'])} "
              f"synced={lm}  newest-tab={newest}")
    guids = [d["guid"] for d in devices]
    for i in range(len(guids)):
        for j in range(i + 1, len(guids)):
            a, b = guids[i], guids[j]
            ov = len(urlsets[a] & urlsets[b])
            if ov:
                print(f"  overlap {a[:8]}∩{b[:8]}: {ov} shared, "
                      f"{len(urlsets[a]-urlsets[b])} only-{a[:8]}, "
                      f"{len(urlsets[b]-urlsets[a])} only-{b[:8]}")

    skip = set()
    if args.skip_urls:
        skip = {l.strip() for l in open(args.skip_urls) if l.strip()}

    # device selection: explicit --device guid prefixes win, then --all-devices;
    # otherwise only the most recently synced record whose name contains
    # "fennec" (falls back to the newest record if none matches, so a renamed
    # device doesn't silently widen the run to every device)
    if args.device:
        sel = [d for d in devices
               if any(d["guid"].startswith(p) for p in args.device)]
        if not sel:
            print("warning: --device matched no device record")
    elif args.all_devices:
        sel = devices
    elif devices:
        fen = [d for d in devices if "fennec" in d["name"].lower()]
        keep = max(fen or devices, key=lambda d: d["last_modified"])
        sel = [keep]
        if not fen:
            print(f"default: no 'Fennec' device record; using newest record "
                  f"{keep['name']} [{keep['guid'][:8]}]")
        skipped = [d for d in devices if d is not keep]
        if skipped:
            print("excluded: " + ", ".join(
                f"{d['name']}[{d['guid'][:8]}]" for d in skipped)
                + " (use --device/--all-devices to include)")

    queue, seen = [], set()
    for d in sel:
        for t in d["tabs"]:
            url = t["url"]
            if url in seen or url in skip:
                continue
            seen.add(url)
            queue.append({
                "device": d["name"], "guid": d["guid"],
                "title": t["title"], "url": url,
                "linktext": linktext(t["title"], url),
                "lastUsed": t["lastUsed"], "status": "pending",
            })
    out = args.out or os.path.join(args.scratch, "queue.json")
    json.dump({"devices": [{"guid": d["guid"], "name": d["name"],
                            "last_modified": d["last_modified"],
                            "tab_count": len(d["tabs"])} for d in devices],
               "queue": queue}, open(out, "w"), indent=1)
    print(f"queue: {len(queue)} tabs → {out}")

if __name__ == "__main__":
    main()
