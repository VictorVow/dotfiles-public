#!/usr/bin/env python3
"""Read an extension's stored data (storage.local and its own IndexedDB) from the profile on disk.

No remote-debug restart needed and safe while Firefox runs: the .sqlite (+ -wal)
files are copied to a temp dir and read from there. Useful for checking an
extension's settings or cache timestamps (e.g. Sidebery's snapshot interval,
uBlock's assetCacheRegistry write times) while diagnosing it.

Format notes (Firefox IndexedDB, which also backs storage.local):
  - Values are snappy-compressed SpiderMonkey structured clones. Large values
    live in <db>.files/<id> instead of inline (file_ids column).
  - String keys are encoded as 0x30 followed by each char + 1.
  - storage.local lives under moz-extension+++<uuid>^userContextId=4294967295;
    the extension's own IndexedDB databases under moz-extension+++<uuid>.

Usage: ff-ext-storage.py [-p PROFILE] EXTENSION            # list databases + keys
       ff-ext-storage.py [-p PROFILE] EXTENSION KEY        # dump KEY as JSON
EXTENSION is a case-insensitive substring of the name, or the add-on id.
"""
import argparse
import json
import re
import shutil
import sqlite3
import struct
import sys
import tempfile
from pathlib import Path


def resolve_extension(profile_dir: Path, query: str):
    """-> (name, addon id, internal uuid)"""
    prefs = (profile_dir / "prefs.js").read_text(errors="replace")
    m = re.search(r'user_pref\("extensions\.webextensions\.uuids", "(.*)"\);', prefs)
    uuids = json.loads(m.group(1).encode().decode("unicode_escape")) if m else {}
    addons = json.loads((profile_dir / "extensions.json").read_text()).get("addons", [])
    hits = [(((a.get("defaultLocale") or {}).get("name") or a["id"]), a["id"]) for a in addons
            if a["id"] == query or query.lower() in ((a.get("defaultLocale") or {}).get("name") or "").lower()]
    hits = [(n, i) for n, i in hits if i in uuids]
    if len(hits) != 1:
        found = ", ".join(n for n, _ in hits) or "none"
        sys.exit(f"error: {query!r} must match exactly one installed extension (matched: {found})")
    name, addon_id = hits[0]
    return name, addon_id, uuids[addon_id]


def varint(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1
        r |= (c & 0x7F) << s; s += 7
        if c < 0x80:
            return r, i


def unsnappy(b: bytes) -> bytes:
    n, i = varint(b, 0)
    out = bytearray()
    while i < len(b):
        t = b[i]; i += 1
        kind = t & 3
        if kind == 0:  # literal
            ln = t >> 2
            if ln >= 60:
                nb = ln - 59; ln = int.from_bytes(b[i:i + nb], "little"); i += nb
            ln += 1
            out += b[i:i + ln]; i += ln
            continue
        if kind == 1:
            ln = ((t >> 2) & 7) + 4; off = ((t >> 5) << 8) | b[i]; i += 1
        elif kind == 2:
            ln = (t >> 2) + 1; off = int.from_bytes(b[i:i + 2], "little"); i += 2
        else:
            ln = (t >> 2) + 1; off = int.from_bytes(b[i:i + 4], "little"); i += 4
        for _ in range(ln):
            out.append(out[-off])
    if len(out) != n:
        raise ValueError(f"snappy: expected {n} bytes, got {len(out)}")
    return bytes(out)


class StructuredClone:
    """Minimal SpiderMonkey structured-clone reader: JSON-like values only."""

    END_OF_KEYS = 0x13

    def __init__(self, b: bytes):
        self.b, self.i, self.objects = b, 0, []

    def _pair(self):
        lo, hi = struct.unpack_from("<II", self.b, self.i); self.i += 8
        return hi, lo

    def _string(self, data):
        n, latin1 = data & 0x7FFFFFFF, data & 0x80000000
        nbytes = n if latin1 else 2 * n
        raw = self.b[self.i:self.i + nbytes]
        self.i += (nbytes + 7) & ~7
        return raw.decode("latin-1") if latin1 else raw.decode("utf-16-le", "replace")

    def _double(self):
        v = struct.unpack_from("<d", self.b, self.i)[0]; self.i += 8
        return v

    def read(self):
        tag, data = self._pair()
        if tag == 0xFFF10000:  # header
            return self.read()
        if tag < 0xFFF00000:   # a bare double occupies the whole pair
            return struct.unpack_from("<d", self.b, self.i - 8)[0]
        t = tag & 0xFFFF
        if t in (0, 1):
            return None
        if t in (2, 0xA):
            return bool(data)
        if t == 3:
            return struct.unpack("<i", struct.pack("<I", data))[0]
        if t == 4:
            return self._string(data)
        if t in (5, 0xC):   # Date (as ms), Number object
            return self._double()
        if t == 0xB:        # String object
            return self.read()
        if t == self.END_OF_KEYS:
            raise StopIteration
        if t in (7, 8):     # Array, Object
            obj = [] if t == 7 else {}
            self.objects.append(obj)
            while True:
                try:
                    k = self.read()
                except StopIteration:
                    return obj
                v = self.read()
                if t == 7:
                    obj.append(v)
                else:
                    obj[str(k)] = v
        if t == 0xD:
            return self.objects[data] if data < len(self.objects) else "<backref>"
        return f"<unsupported tag {t:#x}>"


def decode_key(raw: bytes) -> str:
    if raw[:1] != b"\x30":
        return f"<non-string key {raw.hex()}>"
    return "".join(chr(c - 1) for c in raw[1:])


def copy_dbs(profile_dir: Path, uuid: str, tmp: Path):
    """Copy every IDB sqlite (+ wal, + .files dir) for the extension; -> [(label, path)]"""
    out = []
    for origin in sorted((profile_dir / "storage/default").glob(f"moz-extension+++{uuid}*")):
        label = "storage.local" if "userContextId=4294967295" in origin.name else "indexedDB"
        for db in sorted((origin / "idb").glob("*.sqlite")):
            dst = tmp / f"{label}-{db.name}"
            shutil.copy2(db, dst)
            for side in (db.with_name(db.name + "-wal"),):
                if side.exists():
                    shutil.copy2(side, dst.with_name(dst.name + "-wal"))
            files = db.with_suffix(".files")
            if files.is_dir():
                shutil.copytree(files, dst.with_suffix(".files"))
            out.append((label, dst))
    return out


def read_value(db: Path, data: bytes, file_ids):
    if file_ids:
        data = (db.with_suffix(".files") / file_ids.lstrip(".").split()[0]).read_bytes()
    return StructuredClone(unsnappy(data)).read()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-p", "--profile", default="VERTEX")
    ap.add_argument("extension")
    ap.add_argument("key", nargs="?")
    args = ap.parse_args()

    profile_dir = Path.home() / ".mozilla/firefox" / args.profile
    name, addon_id, uuid = resolve_extension(profile_dir, args.extension)

    with tempfile.TemporaryDirectory(prefix="ff-ext-storage.") as tmp:
        dbs = copy_dbs(profile_dir, uuid, Path(tmp))
        if not dbs:
            sys.exit(f"error: no stored data for {name} ({addon_id})")
        for label, db in dbs:
            con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            store = ", ".join(r[0] for r in con.execute("select name from object_store"))
            rows = con.execute(
                "select key, data, file_ids, length(data) from object_data order by key").fetchall()
            if args.key is None:
                print(f"== {name} {label} [{store}] ({db.name.split('-', 1)[1]})")
                for k, _, fids, ln in rows:
                    where = f"file {fids.lstrip('.')}" if fids else f"{ln} B"
                    print(f"  {decode_key(k)[:90]:90} {where}")
                continue
            for k, data, fids, _ in rows:
                if decode_key(k) == args.key:
                    print(f"# {name} {label} [{store}]", file=sys.stderr)
                    print(json.dumps(read_value(db, data, fids), indent=1, ensure_ascii=False))
                    return
        if args.key is not None:
            sys.exit(f"error: key {args.key!r} not found for {name}")


if __name__ == "__main__":
    main()
