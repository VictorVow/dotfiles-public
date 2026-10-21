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

source "$(dirname "$0")/transcript-common.sh"
ts_init
ts_defaults
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

ts_resolve "$@"
[ "${#FILE_TARGETS[@]}" -gt 0 ] || [ "${#DB_TARGETS[@]}" -gt 0 ] || [ -n "$CASS_DB" ] || { echo "no transcript stores exist" >&2; exit 2; }

ts_lock || exit 2
ts_targets_json
export STATE_FILE FULL REPORT CONF CASS_DB DIR
python3 - "$REPORT_DIR" <<'PYEOF'
import json, os, sys, sqlite3
sys.path.insert(0, os.environ["DIR"])
from transcript_common import (gitleaks_scan, collect_targets, prune_state,
                               db_recently_modified, dump_sqlite_rows,
                               dump_cass_convs, save_state)

report_dir = sys.argv[1]
file_targets = json.loads(os.environ["FILE_TARGETS_JSON"])
db_targets = json.loads(os.environ["DB_TARGETS_JSON"])
state_file = os.environ["STATE_FILE"]
full = os.environ["FULL"] == "1"
conf = os.environ["CONF"]

state = json.load(open(state_file))

scan_errors = []

# ---------------- files -----------------------------------------------------
to_scan, seen = collect_targets(file_targets, state, full)

fresh = []
for p in to_scan:
    hits = gitleaks_scan(conf, p, os.path.join(report_dir, "frag.json"),
                         scan_errors, redact=True)
    if hits is None:
        continue  # leave previous state untouched
    st = os.stat(p)
    state[p] = {"mtime": st.st_mtime, "size": st.st_size,
                "findings": [{"rule": f["RuleID"], "line": f["StartLine"]}
                             for f in hits]}
    fresh.extend(hits)

prune_state(state, file_targets, db_targets, seen)

# ---------------- opencode v1 sqlite ----------------------------------------
db_fresh = []   # pseudo-findings for the report
import time; now = time.time()
for db_i, db in enumerate(db_targets):
    if not os.path.exists(db): continue
    # Skip dumping a DB a live agent may be writing -- an inconsistent dump
    # yields false findings.
    if db_recently_modified(db, now):
        print(f"skip {db}: modified <5min ago (live session?)", file=sys.stderr)
        continue
    key = f"sqlite://{db}"
    ent = state.get(key, {"hwm": 0, "dirty": []})
    hwm = 0 if full else ent.get("hwm", 0)
    dirty_rows = {(d["table"], d["id"]) for d in ent.get("dirty", [])}
    dump = os.path.join(report_dir, f"rows-{db_i}")

    try:
        row_keys, new_hwm = dump_sqlite_rows(db, dump, hwm, dirty_rows)
    except sqlite3.Error as e:
        print(f"skip {db}: {e}", file=sys.stderr); continue

    if not row_keys:
        state[key] = {"hwm": new_hwm, "dirty": ent.get("dirty", [])}
        continue

    hits = gitleaks_scan(conf, dump,
                         os.path.join(report_dir, "rows-frag.json"),
                         scan_errors, redact=True)
    if hits is None:
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
        conv_files, new_chwm = dump_cass_convs(
            cass_db, os.path.join(report_dir, "cass-convs"), chwm, cdirty)
    except sqlite3.Error as e:
        print(f"skip {cass_db}: {e}", file=sys.stderr); conv_files = {}

    chits = []
    if conv_files:
        chits = gitleaks_scan(conf, os.path.join(report_dir, "cass-convs"),
                              os.path.join(report_dir, "cass-frag.json"),
                              scan_errors, redact=True)
    if chits is not None:
        hit_paths = set()
        for h in chits:
            fn = h.get("File")
            if fn in conv_files:
                spath = conv_files[fn]
                hit_paths.add(spath)
                h["File"] = f"cass:{spath}"
                db_fresh.append(h)
        still_cdirty = sorted(cdirty & set(conv_files.values()) | hit_paths)
        state[ckey] = {"hwm": new_chwm, "dirty": still_cdirty}
        if hit_paths:
            pending = set(state.get("cass://pending", [])) | hit_paths
            state["cass://pending"] = sorted(pending)

save_state(state_file, state)

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
