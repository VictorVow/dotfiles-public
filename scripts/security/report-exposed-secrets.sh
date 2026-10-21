#!/usr/bin/env bash
#
# report-exposed-secrets.sh — audit agent transcripts for leaked secrets.
#
# Scans the transcript/session stores of local coding agents with gitleaks and
# prints a grouped summary (rule × file/row) plus the total. The redacted JSON
# report is written to $XDG_STATE_HOME/transcript-scrub/last-report.json and its
# path printed last; gitleaks runs with --redact so no plaintext secrets land
# on disk.
#
# Incremental + repeatable: shares a state file with scrub-transcripts.sh at
# $XDG_STATE_HOME/transcript-scrub/state.json. File entries map to
# {mtime, size, findings:[{rule,line}]}; opencode v1 sqlite DBs live under
# "sqlite://<db>" keys carrying a high-water mark on row time_updated plus a
# dirty-row list — secrets are never persisted, only which files/rows were hit.
# --full ignores the cache.
#
# Read-only: never touches scanned files or DBs.
#
# Usage:
#   report-exposed-secrets.sh                  # scan default stores
#   report-exposed-secrets.sh DIR [DIR...]     # scan specific dirs/files
#   report-exposed-secrets.sh --full           # force rescan of every file/row
#   report-exposed-secrets.sh --quiet          # JSON report path only
#
# Exit code: 0 = clean, 1 = findings, 2 = scan error.
#
set -euo pipefail

DIR="$(dirname "$0")"
CONF="$DIR/gitleaks-scrub.toml"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/transcript-scrub"
STATE_FILE="$STATE_DIR/state.json"
REPORT_DIR="$(mktemp -d)"
trap 'rm -rf "$REPORT_DIR"' EXIT
REPORT="$STATE_DIR/last-report.json"

QUIET=0 FULL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1; shift ;;
    --full)  FULL=1; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

CASS_DATA_DIR="${CASS_DATA_DIR:-$HOME/.local/share/coding-agent-search}"
# raw-mirror is cass-owned + content-addressed; the archive is scanned via
# agent_search.db (CASS_DB) instead.
FILE_TARGETS=(
  "$HOME/.claude/projects"
  "$HOME/.config/codex/sessions"
  "$HOME/.gemini"
  "$HOME/.openclaw"
  "$HOME/.copilot/session-state"
  "$HOME/.local/share/devin"
  "$HOME/.local/share/opencode/storage"
  "$HOME/.opencode1/data/opencode/storage"
)
DB_TARGETS=(
  "$HOME/.local/share/opencode/opencode.db"
  "$HOME/.opencode1/data/opencode/opencode.db"
)
CASS_DB="$CASS_DATA_DIR/agent_search.db"

if [ "$#" -gt 0 ]; then
  FILE_TARGETS=(); DB_TARGETS=(); CASS_DB=""
  for t in "$@"; do
    [ -e "$t" ] || continue
    if [[ "$t" == *.db ]]; then DB_TARGETS+=("$(readlink -f "$t")")
    else FILE_TARGETS+=("$(readlink -f "$t")"); fi
  done
else
  _f=(); for t in "${FILE_TARGETS[@]}"; do [ -e "$t" ] && _f+=("$(readlink -f "$t")"); done; FILE_TARGETS=("${_f[@]+"${_f[@]}"}")
  _d=(); for t in "${DB_TARGETS[@]}";   do [ -e "$t" ] && _d+=("$(readlink -f "$t")"); done; DB_TARGETS=("${_d[@]+"${_d[@]}"}")
fi
[ "${#FILE_TARGETS[@]}" -gt 0 ] || [ "${#DB_TARGETS[@]}" -gt 0 ] || [ -n "$CASS_DB" ] || { echo "no transcript stores exist" >&2; exit 2; }

mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"
# Serialise with scrub-transcripts.sh: concurrent runs interleave gitleaks
# invocations and overwrite each other's state file.
exec 9>"$STATE_DIR/lock"
flock -n 9 || { echo "another transcript-scrub run is in progress" >&2; exit 2; }

FILE_TARGETS_JSON="$(printf '%s\n' "${FILE_TARGETS[@]+"${FILE_TARGETS[@]}"}" | python3 -c 'import sys,json; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')"
DB_TARGETS_JSON="$(printf '%s\n' "${DB_TARGETS[@]+"${DB_TARGETS[@]}"}" | python3 -c 'import sys,json; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')"
export STATE_FILE FULL REPORT CONF CASS_DB FILE_TARGETS_JSON DB_TARGETS_JSON
python3 - "$REPORT_DIR" <<'PYEOF'
import json, os, sys, subprocess, sqlite3

report_dir = sys.argv[1]
file_targets = json.loads(os.environ["FILE_TARGETS_JSON"])
db_targets = json.loads(os.environ["DB_TARGETS_JSON"])
state_file = os.environ["STATE_FILE"]
full = os.environ["FULL"] == "1"
conf = os.environ["CONF"]

state = json.load(open(state_file))

scan_errors = []

def scan_file(p):
    frag = os.path.join(report_dir, "frag.json")
    if os.path.exists(frag): os.remove(frag)
    r = subprocess.run(
        ["gitleaks", "dir", "--config", conf, "--no-banner", "--exit-code", "0",
         "--redact", "--report-format", "json", "--report-path", frag, p],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=False)
    if r.returncode != 0:
        scan_errors.append(f"{p}: gitleaks exited {r.returncode}: {r.stderr.strip()[:200]}")
        return None
    try: return json.load(open(frag))
    except Exception as e:
        scan_errors.append(f"{p}: unreadable gitleaks report: {e}")
        return None

# ---------------- files -----------------------------------------------------
to_scan, seen = [], set()
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

fresh = []
for p in to_scan:
    hits = scan_file(p)
    if hits is None:
        continue  # leave previous state untouched
    st = os.stat(p)
    state[p] = {"mtime": st.st_mtime, "size": st.st_size,
                "findings": [{"rule": f["RuleID"], "line": f["StartLine"]}
                             for f in hits]}
    fresh.extend(hits)

# Prune state only within the roots we walked this run -- a partial run must
# not wipe entries belonging to other targets.
prune_roots = [os.path.realpath(r) for r in file_targets]
for k in [k for k in list(state) if k not in seen and not k.startswith("sqlite://")
          and any(os.path.realpath(k) == r or os.path.realpath(k).startswith(r + os.sep)
                  for r in prune_roots)]:
    del state[k]
# Same for sqlite: drop only keys whose db was targeted this run and is gone.
db_prune = {os.path.realpath(d) for d in db_targets}
for k in [k for k in list(state) if k.startswith("sqlite://")
          and os.path.realpath(k[len("sqlite://"):]) in db_prune
          and not os.path.exists(k[len("sqlite://"):])]:
    del state[k]

# ---------------- opencode v1 sqlite ----------------------------------------
db_fresh = []   # pseudo-findings for the report
import time; now = time.time()
for db in db_targets:
    if not os.path.exists(db): continue
    # WAL mode: writes land in <db>-wal and the main file's mtime barely moves,
    # so take the newest of db/-wal/-shm. Skip dumping a DB a live agent may be
    # writing -- an inconsistent dump yields false findings. Applies under
    # --full too.
    db_mtime = max(
        (os.path.getmtime(f) for f in (db, db + "-wal", db + "-shm")
         if os.path.exists(f)),
        default=0)
    if now - db_mtime < 300:
        print(f"skip {db}: modified <5min ago (live session?)", file=sys.stderr)
        continue
    key = f"sqlite://{db}"
    ent = state.get(key, {"hwm": 0, "dirty": []})
    hwm = 0 if full else ent.get("hwm", 0)
    dirty_rows = {(d["table"], d["id"]) for d in ent.get("dirty", [])}

    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    except sqlite3.Error as e:
        print(f"skip {db}: {e}", file=sys.stderr); continue

    dump = os.path.join(report_dir, f"rows-{len(db_fresh)}")
    os.makedirs(dump, exist_ok=True)
    row_keys = {}
    new_hwm = hwm
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
        state[key] = {"hwm": new_hwm, "dirty": ent.get("dirty", [])}
        continue

    frag = os.path.join(report_dir, "rows-frag.json")
    if os.path.exists(frag): os.remove(frag)
    r = subprocess.run(
        ["gitleaks", "dir", "--config", conf, "--no-banner", "--exit-code", "0",
         "--redact", "--report-format", "json", "--report-path", frag, dump],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=False)
    if r.returncode != 0:
        scan_errors.append(f"{db}: gitleaks exited {r.returncode}: {r.stderr.strip()[:200]}")
        continue
    try: hits = json.load(open(frag))
    except Exception as e:
        scan_errors.append(f"{db}: unreadable gitleaks report: {e}")
        continue

    # surface findings + mark those rows dirty so the scrubber re-checks them
    prev_dirty = {(d["table"], d["id"]) for d in ent.get("dirty", [])}
    now_dirty = set(prev_dirty)
    for h in hits:
        fn = h.get("File")
        if fn in row_keys:
            table, rid = row_keys[fn]
            now_dirty.add((table, rid))
            h["File"] = f"{os.path.basename(db)}:{table}:{rid}"
            db_fresh.append(h)
    state[key] = {"hwm": new_hwm,
                  "dirty": [{"table": t, "id": i} for t, i in sorted(now_dirty)]}

# ---------------- cass archive (agent_search.db) -----------------------------
# Dump messages.content per conversation (newer than hwm or still dirty),
# gitleaks-scan once, surface hits. Hit convs go into the cass://<db> dirty
# list AND cass://pending so the scrubber forgets them on its next run.
cass_db = os.environ.get("CASS_DB", "")
if cass_db and os.path.exists(cass_db):
    ckey = f"cass://{cass_db}"
    cent = state.get(ckey, {"hwm": 0, "dirty": []})
    chwm = 0 if full else cent.get("hwm", 0)
    cdirty = set(cent.get("dirty", []))

    try:
        con = sqlite3.connect(f"file:{cass_db}?mode=ro", uri=True)
    except sqlite3.Error as e:
        print(f"skip {cass_db}: {e}", file=sys.stderr); con = None
    if con:
        conv_ids = {}
        new_chwm = chwm
        for cid, spath, lmc in con.execute(
                "select id, source_path, last_message_created_at from conversations"):
            ts = lmc or 0
            if ts <= chwm and spath not in cdirty:
                continue
            if ts > new_chwm: new_chwm = ts
            conv_ids[cid] = spath
        cdump = os.path.join(report_dir, "cass-convs")
        os.makedirs(cdump, exist_ok=True)
        conv_files = {}
        for cid, spath in conv_ids.items():
            rows = [r[0] for r in con.execute(
                "select content from messages where conversation_id = ? order by idx",
                (cid,))]
            fn = os.path.join(cdump, f"conv--{cid}")
            with open(fn, "w") as fh: fh.write("\n".join(x or "" for x in rows))
            conv_files[fn] = spath
        con.close()

        frag = os.path.join(report_dir, "cass-frag.json")
        if os.path.exists(frag): os.remove(frag)
        chits = []
        if conv_files:
            r = subprocess.run(
                ["gitleaks", "dir", "--config", conf, "--no-banner",
                 "--exit-code", "0", "--redact",
                 "--report-format", "json", "--report-path", frag, cdump],
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=False)
            if r.returncode != 0:
                scan_errors.append(f"{cass_db}: gitleaks exited {r.returncode}: {r.stderr.strip()[:200]}")
                chits = None
            else:
                try: chits = json.load(open(frag))
                except Exception as e:
                    scan_errors.append(f"{cass_db}: unreadable gitleaks report: {e}")
                    chits = None
        if chits is not None:
            hit_paths = set()
            for h in chits:
                fn = h.get("File")
                if fn in conv_files:
                    spath = conv_files[fn]
                    hit_paths.add(spath)
                    h["File"] = f"cass:{spath}"
                    db_fresh.append(h)
            still_cdirty = sorted(cdirty & set(conv_ids.values()) | hit_paths)
            state[ckey] = {"hwm": new_chwm, "dirty": still_cdirty}
            if hit_paths:
                pending = set(state.get("cass://pending", [])) | hit_paths
                state["cass://pending"] = sorted(pending)

with open(state_file + ".tmp", "w") as fh:
    json.dump(state, fh)
os.replace(state_file + ".tmp", state_file)

with open(os.path.join(report_dir, "scan-errors.txt"), "w") as fh:
    fh.write("\n".join(scan_errors))

# merge: fresh file findings + stored file findings + db findings
merged = list(fresh)
seen_files = {f["File"] for f in fresh}
for p, ent in state.items():
    # sqlite://, cass:// keys and cass://pending (a list, not a dict) aren't
    # file entries -- the db findings are already in db_fresh.
    if "://" in p or p in seen_files or not isinstance(ent, dict): continue
    for fnd in ent.get("findings") or []:
        merged.append({"File": p, "RuleID": fnd["rule"], "StartLine": fnd["line"],
                       "Secret": None})
merged += db_fresh

with open(os.environ["REPORT"], "w") as fh:
    json.dump(merged, fh)
PYEOF

python3 - "$REPORT" "$QUIET" <<'EOF'
import json, sys, os, collections
report, quiet = sys.argv[1], sys.argv[2] == "1"
try:
    findings = json.load(open(report))
except json.JSONDecodeError:
    findings = []
if quiet:
    print(report); sys.exit(0)
if not findings:
    print("clean — no secrets found")
by = collections.Counter((f["File"], f["RuleID"]) for f in findings)
for (path, rule), n in sorted(by.items()):
    disp = path if ":" in path and not path.startswith("/") \
        else os.path.relpath(path, os.path.expanduser("~"))
    print(f"{n:4d}  {rule:<35} {disp}")
files = {f["File"] for f in findings}
print(f"\ntotal: {len(findings)} findings in {len(files)} files/rows")
print(f"report: {report}")
EOF

if [ -s "$REPORT_DIR/scan-errors.txt" ]; then
  sed 's/^/scan error: /' "$REPORT_DIR/scan-errors.txt" >&2
  exit 2
fi
if [ "$(python3 -c "import json;print(len(json.load(open('$REPORT'))))" 2>/dev/null || echo 0)" -gt 0 ]; then
  exit 1
fi
exit 0
