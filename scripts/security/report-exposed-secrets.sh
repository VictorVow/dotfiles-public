#!/usr/bin/env bash
#
# report-exposed-secrets.sh — audit agent transcripts for leaked secrets.
#
# Scans the transcript/session stores of local coding agents with gitleaks and
# prints a grouped summary (rule × file) plus the total. The JSON report is kept
# under a temp dir and its path printed last.
#
# Incremental + repeatable: shares a state file with scrub-transcripts.sh at
# $XDG_STATE_HOME/transcript-scrub/state.json mapping file → {mtime, size,
# findings:[{rule,line}]} — secrets themselves are never persisted, only which
# files/rules were hit, so re-running is cheap and a scrub can re-resolve the
# literal values. --full ignores the cache.
#
# Read-only: never touches scanned files.
#
# Usage:
#   report-exposed-secrets.sh                  # scan default transcript dirs
#   report-exposed-secrets.sh DIR [DIR...]     # scan specific dirs/files
#   report-exposed-secrets.sh --full           # force rescan of every file
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

if [ "$#" -eq 0 ]; then
  set -- \
    "$HOME/.claude/projects" \
    "$HOME/.config/codex/sessions" \
    "$HOME/.gemini" \
    "$HOME/.openclaw" \
    "$HOME/.copilot/session-state" \
    "$HOME/.local/share/devin"
  # opencode sessions live in sqlite (opencode.db) — not file-scannable;
  # scrub-transcripts.sh handles the cass archive via cass forget.
fi

targets=()
for t in "$@"; do [ -e "$t" ] && targets+=("$(readlink -f "$t")"); done
[ "${#targets[@]}" -gt 0 ] || { echo "no transcript dirs exist" >&2; exit 2; }

mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"

export STATE_FILE FULL REPORT CONF
python3 - "$REPORT_DIR" "${targets[@]}" <<'PYEOF'
import json, os, sys, subprocess, tempfile

report_dir = sys.argv[1]
targets = sys.argv[2:]
state_file = os.environ["STATE_FILE"]
full = os.environ["FULL"] == "1"
conf = os.environ["CONF"]

state = json.load(open(state_file))

# Enumerate files under targets; pick ones needing a scan.
to_scan = []
seen = set()
for root in targets:
    paths = [root] if os.path.isfile(root) else (
        os.path.join(d, f) for d, _ds, fs in os.walk(root) for f in fs)
    for p in paths:
        if not os.path.isfile(p):
            continue
        try:
            st = os.stat(p)
        except OSError:
            continue
        seen.add(p)
        ent = state.get(p)
        needs = full or not ent or ent["mtime"] != st.st_mtime or ent["size"] != st.st_size \
            or ent.get("findings")  # re-scan files with findings so we have fresh Secrets
        if needs:
            to_scan.append(p)

# Scan changed files one at a time (gitleaks `dir` also accepts a file path).
fresh = []
for p in to_scan:
    frag = os.path.join(report_dir, "frag.json")
    subprocess.run(
        ["gitleaks", "dir", "--config", conf, "--no-banner", "--exit-code", "0",
         "--report-format", "json", "--report-path", frag, p],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    try:
        frag_findings = json.load(open(frag))
    except Exception:
        frag_findings = []
    st = os.stat(p)
    state[p] = {
        "mtime": st.st_mtime, "size": st.st_size,
        # persist only rule+line — never the Secret value
        "findings": [{"rule": f["RuleID"], "line": f["StartLine"]} for f in frag_findings],
    }
    fresh.extend(frag_findings)

# Drop state entries for files that no longer exist.
for k in [k for k in state if k not in seen]:
    del state[k]

with open(state_file + ".tmp", "w") as fh:
    json.dump(state, fh)
os.replace(state_file + ".tmp", state_file)

# Merge fresh findings (have Secret) with stored findings for unchanged files
# (Secret unknown — scrubber will re-scan those files; report shows them anyway).
merged = list(fresh)
for p, ent in state.items():
    if p in {f["File"] for f in fresh}:
        continue
    for fnd in ent.get("findings") or []:
        merged.append({"File": p, "RuleID": fnd["rule"], "StartLine": fnd["line"],
                       "Secret": None, "StartColumn": None, "EndColumn": None})

with open(os.environ["REPORT"], "w") as fh:
    json.dump(merged, fh)

print(len(to_scan), file=sys.stderr)  # count of files actually scanned
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
    print(f"{n:4d}  {rule:<35} {os.path.relpath(path, os.path.expanduser('~'))}")
files = {f["File"] for f in findings}
print(f"\ntotal: {len(findings)} findings in {len(files)} files")
print(f"report: {report}")
EOF

if [ "$(python3 -c "import json;print(len(json.load(open('$REPORT'))))" 2>/dev/null || echo 0)" -gt 0 ]; then
  exit 1
fi
exit 0
