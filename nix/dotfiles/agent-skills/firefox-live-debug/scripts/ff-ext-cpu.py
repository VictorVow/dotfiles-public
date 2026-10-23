#!/usr/bin/env python3
"""Attribute extension-process CPU to individual extensions in a Gecko profile dump.

Complements ff-analyze-profile.py: when it reports "no api_call markers" but the
parent main thread is still busy in recvAPICall / tabs.query, this names the
extension responsible. It walks every sample of the WebExtensions process main
thread and credits each extension whose moz-extension://<uuid>/ code is on the
stack. UUIDs are mapped to names via the profile's prefs.js + extensions.json.

Output:
  1. Per-extension share of samples (and approximate CPU-ms).
  2. A timeline: per-extension share per BUCKET seconds. Shows whether work is a
     one-shot startup cost (e.g. uBlock compiling filter lists) or a steady loop
     (e.g. LeechBlock's 1 s tabs.query ticker).
  3. With --ext NAME: that extension's innermost (own-code) hot frames.

Percentages include idle samples, so compare extensions against each other rather
than reading them as absolute CPU load. Child-process sample times are in ms.

Usage: ff-ext-cpu.py PROFILE_JSON [--profile-dir ~/.mozilla/firefox/VERTEX]
           [--process WebExtensions] [--bucket 30] [--from S] [--to S]
           [--ext NAME] [--top N]
"""
import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

EXT_RE = re.compile(r"moz-extension://([0-9a-f-]{36})/")


def extension_names(profile_dir: Path) -> dict:
    """uuid -> human name, via the uuid pref and extensions.json."""
    prefs = (profile_dir / "prefs.js").read_text(errors="replace")
    m = re.search(r'user_pref\("extensions\.webextensions\.uuids", "(.*)"\);', prefs)
    uuids = json.loads(m.group(1).encode().decode("unicode_escape")) if m else {}
    names = {}
    ext_json = profile_dir / "extensions.json"
    if ext_json.exists():
        for a in json.loads(ext_json.read_text()).get("addons", []):
            names[a["id"]] = (a.get("defaultLocale") or {}).get("name") or a["id"]
    return {u: names.get(i, i) for i, u in uuids.items()}


def all_threads(profile: dict):
    for t in profile.get("threads", []):
        yield t
    for child in profile.get("processes", []):
        yield from all_threads(child)


def columns(table: dict) -> dict:
    return {k: [row[i] if i < len(row) else None for row in table["data"]]
            for k, i in table["schema"].items()}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("profile_json")
    ap.add_argument("--profile-dir", default=str(Path.home() / ".mozilla/firefox/VERTEX"))
    ap.add_argument("--process", default="WebExtensions", help="processName to analyze")
    ap.add_argument("--bucket", type=float, default=30, help="timeline bucket size, seconds")
    ap.add_argument("--from", dest="t_from", type=float, default=0, help="window start, s from first sample")
    ap.add_argument("--to", dest="t_to", type=float, default=float("inf"), help="window end, s")
    ap.add_argument("--ext", help="show hot frames for extensions whose name contains this")
    ap.add_argument("--top", type=int, default=10)
    args = ap.parse_args()

    profile = json.loads(Path(args.profile_json).read_text())
    interval = profile.get("meta", {}).get("interval", 1)
    names = extension_names(Path(args.profile_dir).expanduser())
    label = lambda u: names.get(u, u[:8])

    threads = [t for t in all_threads(profile)
               if t.get("processName") == args.process and t["name"] == "GeckoMain"]
    if not threads:
        sys.exit(f"error: no GeckoMain thread for process {args.process!r} in profile")

    for t in threads:
        strings = t.get("stringTable") or t.get("stringArray")
        S, F, K = columns(t["samples"]), columns(t["frameTable"]), columns(t["stackTable"])
        t0 = S["time"][0]

        # Per stack index: the set of extensions on it and each one's innermost frame.
        cache = {}

        def exts_on(stack):
            if stack in cache:
                return cache[stack]
            found, cur = {}, stack
            while cur is not None:
                loc = strings[F["location"][K["frame"][cur]]]
                m = EXT_RE.search(loc)
                if m and m.group(1) not in found:
                    found[m.group(1)] = EXT_RE.sub("", loc)
                cur = K["prefix"][cur]
            cache[stack] = found
            return found

        total, per_ext = 0, Counter()
        buckets, bucket_total = defaultdict(Counter), Counter()
        frames = defaultdict(Counter)
        for stack, tm in zip(S["stack"], S["time"]):
            rel = (tm - t0) / 1000
            if not (args.t_from <= rel < args.t_to):
                continue
            total += 1
            b = int(rel // args.bucket)
            bucket_total[b] += 1
            for u, leaf in (exts_on(stack) if stack is not None else {}).items():
                per_ext[u] += 1
                buckets[b][u] += 1
                frames[u][leaf] += 1

        span = (S["time"][-1] - t0) / 1000
        print(f"== {args.process} GeckoMain: {total} samples in window, capture span {span:.0f}s")
        top = per_ext.most_common(args.top)
        for u, c in top:
            print(f"  {100 * c / max(total, 1):5.1f}%  ~{c * interval / 1000:6.1f}s  {label(u)}")

        cols = sorted(bucket_total)
        print(f"\n== timeline (% of samples per {args.bucket:g}s bucket)")
        print(f"{'':28}" + "".join(f"{int(b * args.bucket):>6}s" for b in cols))
        for u, _ in top:
            row = "".join(f"{100 * buckets[b][u] / bucket_total[b]:7.1f}" for b in cols)
            print(f"{label(u)[:27]:28}{row}")

        if args.ext:
            for u in per_ext:
                if args.ext.lower() in label(u).lower():
                    print(f"\n== innermost own-code frames: {label(u)}")
                    for leaf, c in frames[u].most_common(args.top):
                        print(f"  {c:7d}  {leaf[:140]}")


if __name__ == "__main__":
    main()
