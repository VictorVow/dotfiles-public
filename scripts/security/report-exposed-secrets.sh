#!/usr/bin/env bash
#
# report-exposed-secrets.sh — audit agent transcripts for leaked secrets.
#
# Scans the transcript/session stores of local coding agents with gitleaks and
# prints a grouped summary (rule × file/row) plus the total. The JSON report is
# kept under a temp dir and its path printed last.
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
REPORT="$REPORT_DIR/report.json"

QUIET=0 FULL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1; shift ;;
    --full)  FULL=1; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

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
[ "${#FILE_TARGETS[@]}" -gt 0 ] || [ "${#DB_TARGETS[@]}" -gt 0 ] || { echo "no transcript stores exist" >&2; exit 2; }

mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"

FILE_TARGETS_JSON="$(printf '%s\n' "${FILE_TARGETS[@]+"${FILE_TARGETS[@]}"}" | python3 -c 'import sys,json; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')"
DB_TARGETS_JSON="$(printf '%s\n' "${DB_TARGETS[@]+"${DB_TARGETS[@]}"}" | python3 -c 'import sys,json; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')"
export STATE_FILE FULL REPORT CONF FILE_TARGETS_JSON DB_TARGETS_JSON
python3 - "$REPORT_DIR" <<'PYEOF'
import json, os, sys, subprocess, sqlite3

report_dir = sys.argv[1]
file_targets = json.loads(os.environ["FILE_TARGETS_JSON"])
db_targets = json.loads(os.environ["DB_TARGETS_JSON"])
state_file = os.environ["STATE_FILE"]
full = os.environ["FULL"] == "1"
conf = os.environ["CONF"]

state = json.load(open(state_file))

def scan_file(p):
    frag = os.path.join(report_dir, "frag.json")
    if os.path.exists(frag): os.remove(frag)
    subprocess.run(
        ["gitleaks", "dir", "--config", conf, "--no-banner", "--exit-code", "0",
         "--report-format", "json", "--report-path", frag, p],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    try: return json.load(open(frag))
    except Exception: return []

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
    st = os.stat(p)
    state[p] = {"mtime": st.st_mtime, "size": st.st_size,
                "findings": [{"rule": f["RuleID"], "line": f["StartLine"]}
                             for f in hits]}
    fresh.extend(hits)

for k in [k for k in list(state) if k not in seen and not k.startswith("sqlite://")]:
    del state[k]

# ---------------- opencode v1 sqlite ----------------------------------------
db_fresh = []   # pseudo-findings for the report
for db in db_targets:
    if not os.path.exists(db): continue
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
    subprocess.run(
        ["gitleaks", "dir", "--config", conf, "--no-banner", "--exit-code", "0",
         "--report-format", "json", "--report-path", frag, dump],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    try: hits = json.load(open(frag))
    except Exception: hits = []

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

with open(state_file + ".tmp", "w") as fh:
    json.dump(state, fh)
os.replace(state_file + ".tmp", state_file)

# merge: fresh file findings + stored file findings + db findings
merged = list(fresh)
seen_files = {f["File"] for f in fresh}
for p, ent in state.items():
    if p.startswith("sqlite://") or p in seen_files: continue
    for fnd in ent.get("findings") or []:
        merged.append({"File": p, "RuleID": fnd["rule"], "StartLine": fnd["line"],
                       "Secret": None})
merged += db_fresh

with open(os.environ["REPORT"], "w") as fh:
    json.dump(merged, fh)
print(len(to_scan), file=sys.stderr)
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

if [ "$(python3 -c "import json;print(len(json.load(open('$REPORT'))))" 2>/dev/null || echo 0)" -gt 0 ]; then
  exit 1
fi
exit 0
