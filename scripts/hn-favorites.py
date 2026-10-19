#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["requests", "beautifulsoup4"]
# ///
"""hn-favorites.py — scan, fetch and un-favorite Hacker News favorites.

Data layer for the hn-favorites-digest skill. Prints JSON for the agent.

Usage:
  hn-favorites.py login [--cookie VALUE]        save the HN `user` cookie (prompts for a password without --cookie)
  hn-favorites.py status                        queue totals + whether the cookie is valid
  hn-favorites.py scan [--min-age-days 3]       walk both favorites views, merge into the queue
  hn-favorites.py next [--limit N] [--min-age-days 3] [--include-failed]
                                                oldest-posted eligible items (pending/written), JSON array;
                                                exit 1 when there are none
  hn-favorites.py comments <id> --out-dir DIR [--chunk-chars 200000]
                                                every comment as text, split into comments-NN.txt chunks
  hn-favorites.py mark <id> written --block <logseq block id/uuid>
  hn-favorites.py mark <id> failed --error MSG
  hn-favorites.py mark <id> pending             reset (e.g. to retry a failed item)
  hn-favorites.py remove <id> [--dry-run]       un-favorite, verify via item?id=, mark done

The user defaults to $HN_USER or "user" (--user overrides).

Notes:
  - The favorites pages are ordered by favoriting time, which HN doesn't expose,
    so the queue is ordered by the item's own posting time, oldest first, and
    "older than N days" means posting age.
  - Comment order: Algolia's /items tree is chronological, so top-level comments
    are reordered by Firebase's ranked `kids`; replies stay chronological.
  - HN throttles hard (robots.txt asks for a 30s crawl delay): at least 5s between
    HN requests, persisted across runs, and exponential backoff on the "Sorry" page.

State: ~/.local/state/hn-favorites/queue.json (state: pending|written|done|failed).
Cookie: ~/.config/hn-favorites/cookie (mode 600).
"""
import argparse
import getpass
import json
import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests
from bs4 import BeautifulSoup

HN = "https://news.ycombinator.com/"
ALGOLIA = "https://hn.algolia.com/api/v1/items/"
FIREBASE = "https://hacker-news.firebaseio.com/v0/item/"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "hn-favorites"
QUEUE = STATE_DIR / "queue.json"
LAST_REQ = STATE_DIR / "last-hn-request"
COOKIE = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "hn-favorites/cookie"
HN_DELAY = 5.0
API_DELAY = 0.5
SORRY = "Sorry, we're not able to serve your requests this quickly"

session = requests.Session()
session.headers["User-Agent"] = "hn-favorites.py (personal favorites digest)"
_last_api = 0.0


def die(msg, code=2):
    print(json.dumps({"error": msg}), file=sys.stderr)
    sys.exit(code)


def now():
    return datetime.now(timezone.utc)


# ── HTTP ─────────────────────────────────────────────────────────────────────

def load_cookie():
    if COOKIE.exists():
        session.cookies.set("user", COOKIE.read_text().strip(), domain="news.ycombinator.com")
        return True
    return False


def hn_get(path):
    """GET an HN page, throttled across runs, with backoff on the rate-limit page."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    for attempt in range(5):
        last = float(LAST_REQ.read_text()) if LAST_REQ.exists() else 0.0
        wait = last + HN_DELAY - time.time()
        if wait > 0:
            time.sleep(wait)
        r = session.get(HN + path, timeout=30)
        LAST_REQ.write_text(str(time.time()))
        if r.status_code in (429, 503) or SORRY in r.text:
            backoff = 60 * 2 ** attempt
            print(f"rate-limited by HN, backing off {backoff}s", file=sys.stderr)
            time.sleep(backoff)
            continue
        r.raise_for_status()
        return r.text
    die("HN kept rate-limiting; try again later")


def api_get(url):
    global _last_api
    wait = _last_api + API_DELAY - time.time()
    if wait > 0:
        time.sleep(wait)
    r = session.get(url, timeout=60)
    _last_api = time.time()
    r.raise_for_status()
    return r.json()


def logged_in(html):
    return 'href="logout' in html


# ── Queue ────────────────────────────────────────────────────────────────────

def load_queue():
    return json.loads(QUEUE.read_text()) if QUEUE.exists() else {}


def save_queue(q):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = QUEUE.with_suffix(".tmp")
    tmp.write_text(json.dumps(q, indent=1, ensure_ascii=False))
    tmp.replace(QUEUE)


def posted(item):
    return datetime.fromisoformat(item["posted"]).replace(tzinfo=timezone.utc)


def ordered(q):
    return sorted(q.values(), key=lambda i: i["posted"])


# ── Favorites parsing ────────────────────────────────────────────────────────

def unfave_href(container, item_id):
    a = container.find("a", href=re.compile(rf"^fave\?id={item_id}&.*un=t"))
    return a["href"] if a else None


def parse_age(span):
    return span["title"].split()[0] if span else None


def parse_submissions(soup):
    for row in soup.select("tr.athing.submission"):
        iid = int(row["id"])
        link = row.select_one("span.titleline > a")
        sub = row.find_next_sibling("tr")
        score = sub.select_one("span.score")
        ncom = next((a.get_text() for a in sub.select("a") if "comment" in a.get_text()), "0")
        url = link["href"]
        yield {
            "id": iid, "kind": "submission", "title": link.get_text(),
            "url": url if url.startswith("http") else HN + url,
            "posted": parse_age(sub.select_one("span.age")),
            "points": int(score.get_text().split()[0]) if score else None,
            "comments": int(re.sub(r"\D", "", ncom) or 0),
            "story_id": iid, "unfave": unfave_href(sub, iid),
        }


def parse_comments(soup):
    for row in soup.select("tr.athing"):
        if "submission" in row.get("class", []):
            continue
        iid = int(row["id"])
        user = row.select_one("a.hnuser")
        on = row.select_one("span.onstory a")
        parent = next((a for a in row.select("span.navs a") if a.get_text() == "parent"), None)
        story_title = on["title"] if on and on.has_attr("title") else (on.get_text() if on else "")
        yield {
            "id": iid, "kind": "comment",
            "title": f"Comment by {user.get_text() if user else '?'} on: {story_title}",
            "url": f"{HN}item?id={iid}",
            "posted": parse_age(row.select_one("span.age")),
            "points": None, "comments": None,
            "story_id": int(on["href"].split("=")[1]) if on else None,
            "parent_id": int(parent["href"].split("=")[1].split("#")[0]) if parent else None,
            "unfave": unfave_href(row, iid),
        }


def walk_favorites(user, comments):
    path = f"favorites?id={user}" + ("&comments=t" if comments else "")
    authed = None
    while path:
        html = hn_get(path)
        authed = logged_in(html) if authed is None else authed
        soup = BeautifulSoup(html, "html.parser")
        yield from (parse_comments(soup) if comments else parse_submissions(soup))
        more = soup.select_one("a.morelink")
        path = more["href"] if more else None


# ── Comment threads ──────────────────────────────────────────────────────────

def html_to_text(html):
    soup = BeautifulSoup(html or "", "html.parser")
    for a in soup.find_all("a"):
        href, text = a.get("href", ""), a.get_text()
        # HN truncates long link text with "..."; the href is the real URL.
        same = text.rstrip(".") and href.startswith(text.rstrip("."))
        a.replace_with(href if same or not text else f"{text} ({href})")
    for p in soup.find_all("p"):
        p.insert_before("\n")
    return soup.get_text().strip()


def render(node, depth, out, counts):
    pad = "  " * depth
    if node.get("text") is None or node.get("author") is None:
        counts["skipped"] += 1
        out.append(f"{pad}[c{node['id']}] [deleted]")
    else:
        counts["comments"] += 1
        out.append(f"{pad}[c{node['id']}] {node['author']} d{depth}:")
        out.extend(f"{pad}  {line}" for line in html_to_text(node["text"]).splitlines() if line.strip())
    for child in node.get("children", []):
        render(child, depth + 1, out, counts)


def cmd_comments(a):
    out_dir = Path(a.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("comments-*.txt"):
        old.unlink()
    tree = api_get(f"{ALGOLIA}{a.id}")
    ranked = (api_get(f"{FIREBASE}{a.id}.json") or {}).get("kids", [])
    rank = {k: i for i, k in enumerate(ranked)}
    tops = sorted(tree.get("children", []), key=lambda c: (rank.get(c["id"], len(rank)), c["created_at_i"]))

    has_post = False
    if tree.get("type") == "comment":
        # A favorited comment: give the story and the parent comment as context.
        story = api_get(f"{FIREBASE}{tree['story_id']}.json") or {}
        lines = [f"Story: {story.get('title')} — {story.get('url') or HN + 'item?id=' + str(tree['story_id'])}"]
        if tree.get("parent_id") and tree["parent_id"] != tree["story_id"]:
            parent = api_get(f"{FIREBASE}{tree['parent_id']}.json") or {}
            lines += [f"\nParent comment by {parent.get('by')}:", html_to_text(parent.get("text"))]
        lines += [f"\nFavorited comment by {tree['author']}:", html_to_text(tree["text"])]
        (out_dir / "post.txt").write_text("\n".join(lines) + "\n")
        has_post = True
    elif tree.get("text"):
        (out_dir / "post.txt").write_text(f"{tree.get('title')}\nby {tree['author']}\n\n{html_to_text(tree['text'])}\n")
        has_post = True

    counts = {"comments": 0, "skipped": 0}
    chunks, cur = [], []
    for top in tops:
        thread = []
        render(top, 0, thread, counts)
        text = "\n".join(thread) + "\n\n"
        if cur and sum(map(len, cur)) + len(text) > a.chunk_chars:
            chunks.append(cur)
            cur = []
        cur.append(text)
    if cur:
        chunks.append(cur)
    files = []
    for n, chunk in enumerate(chunks, 1):
        f = out_dir / f"comments-{n:02d}.txt"
        f.write_text("".join(chunk))
        files.append(str(f))
    print(json.dumps({"id": a.id, "chunks": len(files), "files": files, **counts,
                      "has_post": has_post, "post": str(out_dir / "post.txt") if has_post else None}))


# ── Commands ─────────────────────────────────────────────────────────────────

def cmd_login(a):
    if a.cookie:
        value = a.cookie.strip().removeprefix("user=").split(";")[0]
    else:
        acct = input("HN username: ")
        pw = getpass.getpass("HN password: ")
        r = session.post(HN + "login", data={"acct": acct, "pw": pw, "goto": "news"}, timeout=30)
        value = session.cookies.get("user")
        if not value:
            die("login failed (wrong password, or HN wants a captcha: use --cookie instead)")
    session.cookies.set("user", value, domain="news.ycombinator.com")
    if not logged_in(hn_get(f"user?id={a.user}")):
        die("cookie not accepted by HN")
    COOKIE.parent.mkdir(parents=True, exist_ok=True)
    COOKIE.touch(mode=0o600)
    COOKIE.chmod(0o600)
    COOKIE.write_text(value)
    print(json.dumps({"ok": True, "cookie": str(COOKIE)}))


def cmd_status(a):
    q = load_queue()
    cutoff = now() - timedelta(days=a.min_age_days)
    counts = {s: sum(i["state"] == s for i in q.values()) for s in ("pending", "written", "done", "failed")}
    eligible = sum(i["state"] in ("pending", "written") and posted(i) <= cutoff for i in q.values())
    cookie = "missing"
    if load_cookie():
        cookie = "valid" if logged_in(hn_get(f"user?id={a.user}")) else "invalid"
    print(json.dumps({"scanned": len(q), **counts, "eligible": eligible, "cookie": cookie}))


def cmd_scan(a):
    load_cookie()
    q = load_queue()
    seen, unfave_links = set(), 0
    for comments in (False, True):
        for item in walk_favorites(a.user, comments):
            seen.add(str(item["id"]))
            unfave_links += bool(item["unfave"])
            rec = q.get(str(item["id"]))
            if rec:
                # Keep progress fields; refresh metadata (don't drop a known unfave link).
                rec.update({k: v for k, v in item.items() if v is not None or k != "unfave"})
            else:
                q[str(item["id"])] = {**item, "state": "pending", "block": None, "error": None,
                                      "added": now().isoformat(timespec="seconds")}
    # Gone from favorites without our `remove` (un-favorited by hand): treat as done.
    for iid, rec in q.items():
        if iid not in seen and rec["state"] == "pending":
            rec["state"] = "done"
            rec["error"] = "no longer in favorites at scan time"
    save_queue(dict(sorted(q.items(), key=lambda kv: kv[1]["posted"])))
    cutoff = now() - timedelta(days=a.min_age_days)
    print(json.dumps({
        "favorites": len(seen),
        "submissions": sum(q[i]["kind"] == "submission" for i in seen),
        "comments": sum(q[i]["kind"] == "comment" for i in seen),
        "unfave_links": unfave_links,
        "eligible": sum(q[i]["state"] in ("pending", "written") and posted(q[i]) <= cutoff for i in seen),
    }))


def cmd_next(a):
    cutoff = now() - timedelta(days=a.min_age_days)
    states = {"pending", "written"} | ({"failed"} if a.include_failed else set())
    items = [i for i in ordered(load_queue()) if i["state"] in states and posted(i) <= cutoff][: a.limit]
    print(json.dumps(items, ensure_ascii=False, indent=1))
    sys.exit(0 if items else 1)


def cmd_mark(a):
    q = load_queue()
    rec = q.get(str(a.id)) or die(f"{a.id} not in queue")
    rec["state"] = a.state
    if a.state == "written":
        rec["block"] = a.block or die("--block is required for written")
    rec["error"] = a.error if a.state == "failed" else None
    rec["updated"] = now().isoformat(timespec="seconds")
    save_queue(q)
    print(json.dumps({"id": a.id, "state": a.state}))


def item_fave_link(item_id):
    """The fave link on item?id= — (href, is_favorited). Needs the cookie."""
    html = hn_get(f"item?id={item_id}")
    if not logged_in(html):
        die("HN cookie missing or expired: ask the user to run `hn-favorites.py login --cookie ...`")
    a = BeautifulSoup(html, "html.parser").find("a", href=re.compile(rf"^fave\?id={item_id}&"))
    if not a:
        die(f"no favorite link found on item?id={item_id}")
    return a["href"], "un=t" in a["href"]


def cmd_remove(a):
    if not load_cookie():
        die("no HN cookie: ask the user to run `hn-favorites.py login --cookie ...`")
    q = load_queue()
    rec = q.get(str(a.id)) or die(f"{a.id} not in queue")
    href = rec.get("unfave")
    if not href:
        href, fav = item_fave_link(a.id)
        if not fav:
            href = None
    if a.dry_run:
        print(json.dumps({"id": a.id, "would_get": HN + href if href else None}))
        return
    for attempt in range(2):
        if href:
            hn_get(href)
        href, fav = item_fave_link(a.id)
        if not fav:
            break
        # Stored auth token was stale: retry once with the fresh link.
    else:
        die(f"{a.id} is still favorited after un-favoriting")
    rec.update(state="done", unfave=None, error=None, updated=now().isoformat(timespec="seconds"))
    save_queue(q)
    print(json.dumps({"id": a.id, "state": "done"}))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--user", default=os.environ.get("HN_USER", "user"))
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("login")
    s.add_argument("--cookie")
    s.set_defaults(fn=cmd_login)

    for name, fn in (("status", cmd_status), ("scan", cmd_scan), ("next", cmd_next)):
        s = sub.add_parser(name)
        s.add_argument("--min-age-days", type=float, default=3)
        s.set_defaults(fn=fn)
        if name == "next":
            s.add_argument("--limit", type=int, default=1)
            s.add_argument("--include-failed", action="store_true")

    s = sub.add_parser("comments")
    s.add_argument("id", type=int)
    s.add_argument("--out-dir", required=True)
    s.add_argument("--chunk-chars", type=int, default=200_000)
    s.set_defaults(fn=cmd_comments)

    s = sub.add_parser("mark")
    s.add_argument("id", type=int)
    s.add_argument("state", choices=["pending", "written", "failed"])
    s.add_argument("--block")
    s.add_argument("--error")
    s.set_defaults(fn=cmd_mark)

    s = sub.add_parser("remove")
    s.add_argument("id", type=int)
    s.add_argument("--dry-run", action="store_true")
    s.set_defaults(fn=cmd_remove)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
