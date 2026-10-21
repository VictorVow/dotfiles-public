#!/usr/bin/env bash
#
# report-exposed-secrets.sh — audit agent transcripts for leaked secrets.
#
# Scans the transcript/session stores of local coding agents with gitleaks and
# prints a grouped summary (rule × file) plus the total. The JSON report is kept
# under a temp dir and its path printed last — feed the same scan to
# scrub-transcripts.sh (or re-run it there) to rewrite hits to [REDACTED:*].
#
# Read-only: never touches scanned files.
#
# Usage:
#   report-exposed-secrets.sh                 # scan default transcript dirs
#   report-exposed-secrets.sh DIR [DIR...]    # scan specific dirs/files
#   report-exposed-secrets.sh --quiet         # JSON path only (for scripting)
#
# Exit code: 0 = clean, 1 = findings, 2 = scan error.
#
set -euo pipefail

QUIET=0
[ "${1-}" = "--quiet" ] && { QUIET=1; shift; }

CONF="$(dirname "$0")/gitleaks-scrub.toml"
REPORT="$(mktemp -d)/report.json"

if [ "$#" -eq 0 ]; then
  set -- \
    "$HOME/.claude/projects" \
    "$HOME/.config/codex/sessions" \
    "$HOME/.gemini" \
    "$HOME/.openclaw" \
    "$HOME/.copilot/session-state" \
    "$HOME/.local/share/devin" \
    "$HOME/.local/share/coding-agent-search/raw-mirror"
  # opencode stores sessions in sqlite (opencode.db) — not scanned; see README.
fi

# Drop targets that don't exist (e.g. agents never used on this machine).
targets=()
for t in "$@"; do [ -e "$t" ] && targets+=("$t"); done
[ "${#targets[@]}" -gt 0 ] || { echo "no transcript dirs exist" >&2; exit 2; }

# gitleaks exits 1 on findings, 0 on clean, 2+ on real errors.
set +e
gitleaks dir --config "$CONF" --no-banner --exit-code 0 \
  --report-format json --report-path "$REPORT" "${targets[@]}"
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "gitleaks failed (exit $rc)" >&2; exit 2; }

python3 - "$REPORT" "$QUIET" <<'EOF'
import json, sys, os, collections

report, quiet = sys.argv[1], sys.argv[2] == "1"
try:
    findings = json.load(open(report))
except json.JSONDecodeError:
    findings = []

if quiet:
    print(report)
    sys.exit(0)

if not findings:
    print("clean — no secrets found")

by = collections.Counter((f["File"], f["RuleID"]) for f in findings)
for (path, rule), n in sorted(by.items()):
    print(f"{n:4d}  {rule:<35} {os.path.relpath(path, os.path.expanduser('~'))}")
files = {f["File"] for f in findings}
print(f"\ntotal: {len(findings)} findings in {len(files)} files")
print(f"report: {report}")
EOF

# propagate clean/findings exit status
if python3 -c "import json,sys; sys.exit(0 if len(json.load(open('$REPORT'))) else 1)" 2>/dev/null; then
  exit 1
fi
exit 0
