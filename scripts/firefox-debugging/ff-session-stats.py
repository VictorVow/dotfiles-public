#!/usr/bin/env python3
"""Inspect a Firefox sessionstore.jsonlz4 without opening the browser.

Prints window/tab counts and the heaviest tabs by serialized size — useful for
judging whether a session is big enough for O(all-tabs) extension APIs
(tabs.query etc.) to become pathological, and for spotting tabs with bloated
history/formdata.

Uses a pure-Python LZ4-block decoder so it needs no third-party packages
(Mozilla's .jsonlz4 = b"mozLz40\\0" + u32 size + LZ4 block).

Usage: ff-session-stats.py [PROFILE_DIR] (default ~/.mozilla/firefox/VERTEX)
"""
import json
import struct
import sys
from pathlib import Path


def lz4_block_decompress(src: bytes) -> bytes:
    dst = bytearray()
    i, n = 0, len(src)
    while i < n:
        token = src[i]; i += 1
        lit_len = token >> 4
        if lit_len == 15:
            while True:
                b = src[i]; i += 1
                lit_len += b
                if b != 255:
                    break
        dst += src[i:i + lit_len]; i += lit_len
        if i >= n:
            break
        offset = struct.unpack_from("<H", src, i)[0]; i += 2
        match_len = token & 0xF
        if match_len == 15:
            while True:
                b = src[i]; i += 1
                match_len += b
                if b != 255:
                    break
        match_len += 4
        start = len(dst) - offset
        for j in range(match_len):
            dst.append(dst[start + j])
    return bytes(dst)


def load_jsonlz4(path: Path) -> dict:
    raw = path.read_bytes()
    if raw[:8] != b"mozLz40\0":
        sys.exit(f"error: {path} is not a mozLz4 file")
    return json.loads(lz4_block_decompress(raw[12:]))


def main():
    profile_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / ".mozilla/firefox/VERTEX"
    path = profile_dir / "sessionstore.jsonlz4"
    if not path.exists():
        # Session of a RUNNING browser lives in sessionstore-backups/recovery.jsonlz4
        path = profile_dir / "sessionstore-backups" / "recovery.jsonlz4"
    if not path.exists():
        sys.exit(f"error: no sessionstore found under {profile_dir}")

    session = load_jsonlz4(path)
    windows = session.get("windows", [])
    total_tabs = sum(len(w.get("tabs", [])) for w in windows)
    print(f"{path}")
    print(f"windows={len(windows)} tabs={total_tabs} closedWindows={len(session.get('_closedWindows', []))}")
    for i, w in enumerate(windows):
        tabs = w.get("tabs", [])
        print(f"  window {i}: {len(tabs)} tabs, {len(w.get('_closedTabs', []))} closed tabs")
        heaviest = sorted(tabs, key=lambda t: len(json.dumps(t)), reverse=True)[:5]
        for t in heaviest:
            entries = t.get("entries", [])
            idx = min(t.get("index", 1), len(entries)) - 1
            url = entries[idx].get("url", "?")[:90] if entries else "?"
            print(f"    {len(json.dumps(t)) // 1024:5d}KB  {len(entries):3d} history entries  {url}")


if __name__ == "__main__":
    main()
