#!/usr/bin/env python3
"""List a Firefox profile's open tabs (window, title, URL) from its session file.

Reads the same file as ff-session-stats.py: sessionstore-backups/recovery.jsonlz4
while the browser runs (Firefox rewrites it every ~15 s), sessionstore.jsonlz4
after a clean shutdown. Doesn't touch the running browser.

Output is tab-separated: window index, tab title, current URL. Pass a filter to
keep only tabs whose title or URL contains it (case-insensitive).

Usage: ff-open-tabs.py [-p PROFILE_DIR] [FILTER]   (default profile ~/.mozilla/firefox/VERTEX)
"""
import argparse
import importlib.util
import signal
from pathlib import Path

# Reuse the pure-Python mozLz4 reader from the sibling script (hyphenated name, so no plain import).
_spec = importlib.util.spec_from_file_location("ff_session_stats", Path(__file__).with_name("ff-session-stats.py"))
_stats = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_stats)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-p", "--profile", type=Path, default=Path.home() / ".mozilla/firefox/VERTEX")
    ap.add_argument("filter", nargs="?", default="")
    args = ap.parse_args()
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # quiet exit when piped into head

    path = args.profile / "sessionstore.jsonlz4"
    if not path.exists():
        path = args.profile / "sessionstore-backups" / "recovery.jsonlz4"
    if not path.exists():
        raise SystemExit(f"error: no sessionstore found under {args.profile}")

    needle = args.filter.lower()
    for w_idx, window in enumerate(_stats.load_jsonlz4(path).get("windows", [])):
        for tab in window.get("tabs", []):
            entries = tab.get("entries", [])
            if not entries:
                continue
            entry = entries[min(tab.get("index", 1), len(entries)) - 1]
            title = " ".join(entry.get("title", "").split())
            url = entry.get("url", "")
            if needle and needle not in title.lower() and needle not in url.lower():
                continue
            print(f"{w_idx}\t{title}\t{url}")


if __name__ == "__main__":
    main()
