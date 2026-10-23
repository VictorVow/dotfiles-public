#!/usr/bin/env python3
"""Analyze a Gecko profile dump for runaway-extension symptoms.

Reports, for the parent process main thread:
  1. Hottest JS frames on-stack (chrome:// / resource:// / moz-extension:// URLs) —
     shows WHAT the main thread is doing (e.g. 40% inside tabs.query serialization).
  2. WebExtension `api_call` marker counts per extension — shows WHO is doing it.

Interpreting the counts: compare against the session's tab count (ff-session-stats.py).
A count ≈ tab count for a per-tab API (tabs.sendMessage, pageAction.setIcon) is
usually a benign one-shot startup sweep. A large count for a GLOBAL API that only
needs one call — tabs.query, windows.getAll — is a runaway loop (GeoSpoof 1.22.14
made ~25 tabs.query/sec). When unsure, capture twice: one-shot sweeps don't recur,
loops do.

Extension ids are mapped to human names via the profile dir's extensions.json.

Usage: ff-analyze-profile.py PROFILE_JSON [--profile-dir ~/.mozilla/firefox/VERTEX] [--top N]
"""
import argparse
import json
import sys
from collections import Counter
from pathlib import Path

# APIs where one call covers the whole browser — hundreds of calls means a loop,
# unlike per-tab APIs whose count naturally matches the tab count at startup.
GLOBAL_APIS = {"tabs.query", "windows.getAll", "windows.getCurrent", "tabs.getCurrent",
               "storage.local.get", "bookmarks.getTree", "history.search"}


def load_extension_names(profile_dir: Path) -> dict:
    names = {}
    ext_json = profile_dir / "extensions.json"
    if ext_json.exists():
        for a in json.loads(ext_json.read_text()).get("addons", []):
            name = (a.get("defaultLocale") or {}).get("name")
            if name:
                names[a["id"]] = name
    return names


def all_threads(profile: dict):
    yield from ((profile.get("meta", {}).get("processType"), t) for t in profile.get("threads", []))
    for child in profile.get("processes", []):
        yield from all_threads(child)


def parent_geckomain(profile: dict):
    for ptype, t in all_threads(profile):
        if t["name"] == "GeckoMain" and ptype in (0, None):
            return t
    for _, t in all_threads(profile):
        if t["name"] == "GeckoMain":
            return t
    sys.exit("error: no GeckoMain thread in profile")


def hot_js_frames(thread: dict, top: int) -> list:
    strings = thread.get("stringTable") or thread.get("stringArray")
    frames = thread["frameTable"]["data"]
    loc_i = thread["frameTable"]["schema"]["location"]
    stacks = thread["stackTable"]["data"]
    prefix_i = thread["stackTable"]["schema"]["prefix"]
    frame_i = thread["stackTable"]["schema"]["frame"]
    samples = thread["samples"]["data"]
    stack_i = thread["samples"]["schema"]["stack"]

    onstack = Counter()
    for s in samples:
        cur, seen, depth = s[stack_i], set(), 0
        while cur is not None and depth < 300:
            f = strings[frames[stacks[cur][frame_i]][loc_i]]
            if "://" in f and f not in seen:
                onstack[f] += 1
                seen.add(f)
            cur = stacks[cur][prefix_i]
            depth += 1
    n = max(len(samples), 1)
    return [(100 * c / n, f) for f, c in onstack.most_common(top)], len(samples)


def api_call_counts(thread: dict) -> Counter:
    markers = thread.get("markers", {})
    schema = markers.get("schema", {})
    data_i = schema.get("data")
    counts = Counter()
    for row in markers.get("data", []):
        payload = row[data_i] if data_i is not None and data_i < len(row) else None
        if isinstance(payload, dict) and "api_call" in str(payload.get("name", "")):
            counts[payload["name"]] += 1
    return counts


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("profile_json", type=Path)
    ap.add_argument("--profile-dir", type=Path, default=Path.home() / ".mozilla/firefox/VERTEX")
    ap.add_argument("--top", type=int, default=20)
    args = ap.parse_args()

    profile = json.loads(args.profile_json.read_text())
    names = load_extension_names(args.profile_dir)
    thread = parent_geckomain(profile)

    frames, n_samples = hot_js_frames(thread, args.top)
    print(f"== hottest JS frames on parent main thread ({n_samples} samples) ==")
    for pct, frame in frames:
        print(f"{pct:5.1f}%  {frame[:150]}")

    print("\n== extension api_call markers (whole capture) ==")
    counts = api_call_counts(thread)
    if not counts:
        print("(none — parent busy-work is not extension API calls; check the frames above)")
    for marker, c in counts.most_common(args.top):
        ext_id, _, call = marker.partition(", api_call: ")
        label = names.get(ext_id, ext_id)
        flag = "  <== loop? (global API, needs 1 call)" if c > 100 and call in GLOBAL_APIS else ""
        print(f"{c:6d}  {label:40.40s} {call}{flag}")


if __name__ == "__main__":
    main()
