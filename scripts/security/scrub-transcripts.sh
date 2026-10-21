#!/usr/bin/env bash
#
# scrub-transcripts.sh — rewrite leaked secrets in agent transcripts to
# [REDACTED:<rule>] in place, and drop leaked conversations from the cass
# archive so the search index stops serving them.
#
# Stores handled:
#   * JSONL/JSON transcript trees (claude, codex, gemini, openclaw, copilot,
#     devin, opencode v2 session_diff files, cass raw-mirror) — spliced on
#     disk via atomic rename.
#   * opencode v1 sqlite (opencode.db: message.data + part.data JSON blobs)
#     — rows dumped to a temp dir, gitleaks-scanned, and patched back with
#     UPDATE ... SET data = replace(data, secret, marker).
#
# Incremental + repeatable: shares the state file written by
# report-exposed-secrets.sh ($XDG_STATE_HOME/transcript-scrub/state.json).
# Files whose mtime/size are unchanged since their last clean scan are skipped;
# files with stored findings are re-scanned so the literal Secret values are
# fresh (state never stores secrets). For sqlite DBs the state key is
# "sqlite://<db>" and carries a high-water mark on the row time_updated — only
# rows newer than the mark (plus rows still marked dirty) are re-scanned.
#
# cass: after splicing a source file we run
#   cass forget --source-glob '**/<basename>' --apply
# so the archive drops the leaked copy; cass-incremental re-indexes the clean
# version on its next run. --no-cass skips this.
#
# Safety:
#   * --dry-run prints what would change, touches nothing (files, sqlite, cass).
#   * files/rows touched in the last 5 minutes are skipped (live session?).
#   * findings whose Secret is <8 bytes are skipped (too risky to splice).
#
# Usage:
#   scrub-transcripts.sh --dry-run            # preview
#   scrub-transcripts.sh                      # scrub everything + cass archive
#   scrub-transcripts.sh DIR|DB [DIR|DB...]   # scrub specific dirs/files/.db
#   scrub-transcripts.sh --no-cass            # skip the cass forget step
#   scrub-transcripts.sh --full               # force rescan of everything
#
set -euo pipefail

DIR="$(dirname "$0")"
CONF="$DIR/gitleaks-scrub.toml"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/transcript-scrub"
STATE_FILE="$STATE_DIR/state.json"
REPORT_DIR="$(mktemp -d)"
REPORT="$REPORT_DIR/report.json"
CASS_BIN="${CASS_BIN:-/home/linuxbrew/.linuxbrew/bin/cass}"
CASS_DATA_DIR="${CASS_DATA_DIR:-$HOME/.local/share/coding-agent-search}"

DRY=0 FULL=0 CASS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --full)    FULL=1; shift ;;
    --no-cass) CASS=0; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

# Default file targets (JSONL/JSON stores) + sqlite targets (opencode v1).
FILE_TARGETS=(
  "$HOME/.claude/projects"
  "$HOME/.config/codex/sessions"
  "$HOME/.gemini"
  "$HOME/.openclaw"
  "$HOME/.copilot/session-state"
  "$HOME/.local/share/devin"
  "$HOME/.local/share/opencode/storage"
  "$HOME/.opencode1/data/opencode/storage"
  "$HOME/.local/share/coding-agent-search/raw-mirror"
)
DB_TARGETS=(
  "$HOME/.local/share/opencode/opencode.db"
  "$HOME/.opencode1/data/opencode/opencode.db"
)

if [ "$#" -gt 0 ]; then
  FILE_TARGETS=(); DB_TARGETS=()
  for t in "$@"; do
    [ -e "$t" ] || continue
    if [[ "$t" == *.db ]]; then DB_TARGETS+=("$(readlink -f "$t")")
    else FILE_TARGETS+=("$(readlink -f "$t")"); fi
  done
else
  _f=(); for t in "${FILE_TARGETS[@]}"; do [ -e "$t" ] && _f+=("$(readlink -f "$t")"); done; FILE_TARGETS=("${_f[@]+"${_f[@]}"}")
  _d=(); for t in "${DB_TARGETS[@]}";   do [ -e "$t" ] && _d+=("$(readlink -f "$t")"); done; DB_TARGETS=("${_d[@]+"${_d[@]}"}")
fi
[ "${#FILE_TARGETS[@]}" -gt 0 ] || [ "${#DB_TARGETS[@]}" -gt 0 ] || { echo "no transcript stores exist" >&2; exit 1; }

mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"

FILE_TARGETS_JSON="$(printf '%s\n' "${FILE_TARGETS[@]+"${FILE_TARGETS[@]}"}" | python3 -c 'import sys,json; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')"
DB_TARGETS_JSON="$(printf '%s\n' "${DB_TARGETS[@]+"${DB_TARGETS[@]}"}" | python3 -c 'import sys,json; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')"
export STATE_FILE FULL REPORT CONF DRY CASS CASS_BIN CASS_DATA_DIR FILE_TARGETS_JSON DB_TARGETS_JSON
python3 - "$REPORT_DIR" <<PYEOF
import json, os, sys, subprocess, sqlite3

report_dir = sys.argv[1]
file_targets = json.loads(os.environ["FILE_TARGETS_JSON"])
db_targets = json.loads(os.environ["DB_TARGETS_JSON"])
state_file = os.environ["STATE_FILE"]
full = os.environ["FULL"] == "1"
conf = os.environ["CONF"]
dry = os.environ["DRY"] == "1"
cass = os.environ["CASS"] == "1"
cass_bin = os.environ["CASS_BIN"]

state = json.load(open(state_file))
import time; now = time.time()

def scan_path(p):
    """gitleaks-scan one file; return findings list."""
    frag = os.path.join(report_dir, "frag.json")
    if os.path.exists(frag): os.remove(frag)
    subprocess.run(
        ["gitleaks", "dir", "--config", conf, "--no-banner", "--exit-code", "0",
         "--report-format", "json", "--report-path", frag, p],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    try: return json.load(open(frag))
    except Exception: return []

skipped_recent = skipped_short = redacted = 0
scrubbed_paths = []

# ---------------- file targets ---------------------------------------------
seen = set()
to_scan = []
for root in file_targets:
    paths = [root] if os.path.isfile(root) else (
        os.path.join(d, f) for d, _ds, fs in os.walk(root) for f in fs)
    for p in paths:
        if not os.path.isfile(p): continue
        try: st = os.stat(p)
        except OSError: continue
        seen.add(p)
        ent = state.get(p)
        if full or not ent or ent["mtime"] != st.st_mtime or ent["size"] != st.st_size \
           or ent.get("findings"):
            to_scan.append(p)

for p in to_scan:
    if now - os.path.getmtime(p) < 300:
        skipped_recent += 1
        continue
    hits = scan_path(p)
    st = os.stat(p)
    if not hits:
        state[p] = {"mtime": st.st_mtime, "size": st.st_size, "findings": []}
        continue

    content = open(p, "rb").read()
    applied = 0
    for h in hits:
        secret = (h.get("Secret") or "").encode()
        if len(secret) < 8:
            skipped_short += 1; continue
        rep = f"[REDACTED:{h['RuleID']}]".encode()
        if secret in content:
            content = content.replace(secret, rep); applied += 1
    if applied:
        if dry:
            print(f"dry-run  {applied:3d}  {os.path.relpath(p, os.path.expanduser('~'))}")
        else:
            tmp = p + ".scrub.tmp"
            with open(tmp, "wb") as fh: fh.write(content)
            os.chmod(tmp, os.stat(p).st_mode & 0o777)
            os.replace(tmp, p)
            print(f"scrubbed {applied:3d}  {os.path.relpath(p, os.path.expanduser('~'))}")
        redacted += applied
        scrubbed_paths.append(p)

    st = os.stat(p)
    if dry or applied == 0:
        still_dirty = hits
    else:
        still_dirty = [h for h in hits if len((h.get("Secret") or "").encode()) < 8]
    state[p] = {"mtime": st.st_mtime, "size": st.st_size,
                "findings": [{"rule": h["RuleID"], "line": h["StartLine"]}
                             for h in still_dirty]}

for k in [k for k in list(state) if k not in seen and not k.startswith("sqlite://")]:
    del state[k]

# ---------------- opencode v1 sqlite targets --------------------------------
# State key "sqlite://<db>" -> {"hwm": <max row time_updated, epoch ms>,
#                             "dirty": [{"table":..,"id":..}]}.
# Each run scans rows newer than hwm plus dirty rows; patched rows become clean.
db_stats = {"rows_scanned": 0, "rows_patched": 0}
for db in db_targets:
    if not os.path.exists(db): continue
    if now - os.path.getmtime(db) < 300 and not full:
        print(f"skip     ---  {db} (modified <5min ago)", file=sys.stderr)
        continue
    key = f"sqlite://{db}"
    ent = state.get(key, {"hwm": 0, "dirty": []})
    hwm = 0 if full else ent.get("hwm", 0)
    dirty_rows = {(d["table"], d["id"]) for d in ent.get("dirty", [])}

    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    except sqlite3.Error as e:
        print(f"skip     ---  {db} ({e})", file=sys.stderr); continue

    # extract candidate rows: newer than hwm or marked dirty
    dump = os.path.join(report_dir, "rows")
    os.makedirs(dump, exist_ok=True)
    new_hwm = hwm
    row_keys = {}  # dump-file path -> (table, rowid)
    for table in ("message", "part"):
        try:
            cur = con.execute(
                f"select id, time_updated, data from {table} where time_updated > ?",
                (hwm,))
        except sqlite3.Error:
            continue
        for rid, tupd, data in cur.fetchall():
            ts = tupd or 0
            if ts > new_hwm: new_hwm = ts
            fn = os.path.join(dump, f"{table}--{rid}")
            with open(fn, "w") as fh: fh.write(data or "")
            row_keys[fn] = (table, rid)
    # re-extract dirty rows regardless of age
    for table, rid in dirty_rows:
        try:
            r = con.execute(f"select data from {table} where id = ?", (rid,)).fetchone()
        except sqlite3.Error:
            r = None
        if r:
            fn = os.path.join(dump, f"{table}--{rid}")
            with open(fn, "w") as fh: fh.write(r[0] or "")
            row_keys[fn] = (table, rid)
    con.close()

    if not row_keys:
        state[key] = {"hwm": new_hwm, "dirty": []}
        continue

    # one gitleaks scan over the whole dump dir
    frag = os.path.join(report_dir, "rows-frag.json")
    if os.path.exists(frag): os.remove(frag)
    subprocess.run(
        ["gitleaks", "dir", "--config", conf, "--no-banner", "--exit-code", "0",
         "--report-format", "json", "--report-path", frag, dump],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    try: hits = json.load(open(frag))
    except Exception: hits = []
    db_stats["rows_scanned"] += len(row_keys)

    # group hits per row
    per_row = {}
    for h in hits:
        fn = h.get("File")
        if fn in row_keys:
            per_row.setdefault(row_keys[fn], []).append(h)

    still_dirty = []
    if not dry and per_row:
        con = sqlite3.connect(db)
    for (table, rid), rowhits in per_row.items():
        if dry:
            print(f"dry-run  {len(rowhits):3d}  {os.path.basename(db)}:{table}:{rid[:16]}…")
            still_dirty.append({"table": table, "id": rid})
            db_stats["rows_patched"] += len(rowhits)
            continue
        row = con.execute(f"select data from {table} where id = ?", (rid,)).fetchone()
        if not row: continue
        data = row[0] or ""
        applied = 0
        for h in rowhits:
            secret = h.get("Secret") or ""
            if len(secret.encode()) < 8:
                skipped_short += 1; continue
            rep = f"[REDACTED:{h['RuleID']}]"
            if secret in data:
                data = data.replace(secret, rep); applied += 1
        if applied:
            con.execute(f"update {table} set data = ? where id = ?", (data, rid))
            db_stats["rows_patched"] += applied
            print(f"scrubbed {applied:3d}  {os.path.basename(db)}:{table}:{rid[:16]}…")
            # secrets <8 remain -> keep dirty
            if any(len((h.get("Secret") or "").encode()) < 8 for h in rowhits):
                still_dirty.append({"table": table, "id": rid})
        else:
            still_dirty.append({"table": table, "id": rid})
    if not dry and per_row:
        con.commit(); con.close()

    state[key] = {"hwm": new_hwm, "dirty": still_dirty}

with open(state_file + ".tmp", "w") as fh:
    json.dump(state, fh)
os.replace(state_file + ".tmp", state_file)

# -- cass archive: forget conversations whose sources we scrubbed -----------
forgotten = 0
if cass and not dry and scrubbed_paths and os.path.exists(cass_bin):
    for p in scrubbed_paths:
        dbpath = os.path.join(os.environ["CASS_DATA_DIR"], "agent_search.db")
        r = subprocess.run(
            [cass_bin, "forget", "--source-glob", f"**/{os.path.basename(p)}",
             "--apply", "--db", dbpath, "--json"],
            capture_output=True, text=True)
        if r.returncode == 0:
            forgotten += 1
        else:
            print(f"cass forget failed for {p}: {r.stderr.strip()[:200]}", file=sys.stderr)
    # opencode v1 sessions appear in cass with a '…/opencode.db/…' pseudo-path;
    # if any db rows were patched, forget the db glob too.
    if db_stats["rows_patched"]:
        r = subprocess.run(
            [cass_bin, "forget", "--source-glob", "**/opencode.db*",
             "--apply", "--db", dbpath, "--json"],
            capture_output=True, text=True)
        if r.returncode == 0:
            print("cass: forgot opencode.db sessions (re-indexed from scrubbed db)")
        else:
            print(f"cass forget failed for opencode.db: {r.stderr.strip()[:200]}", file=sys.stderr)

print(f"\n{redacted} file secrets {'would be ' if dry else ''}redacted "
      f"({skipped_recent} live/recent skipped, {skipped_short} <8-byte skipped); "
      f"sqlite: {db_stats['rows_scanned']} rows scanned, "
      f"{db_stats['rows_patched']} secrets {'would be ' if dry else ''}patched")
if forgotten:
    print(f"cass: forgot {forgotten} file conversations")
if dry:
    print("(dry-run: nothing changed)")
PYEOF
