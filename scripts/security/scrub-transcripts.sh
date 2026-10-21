#!/usr/bin/env bash
#
# scrub-transcripts.sh — rewrite leaked secrets in agent transcripts to
# [REDACTED:<rule>] in place.
#
# Runs the same gitleaks scan as report-exposed-secrets.sh, then splices each
# finding's Secret value out of the file (literal-value replacement inside the
# containing line — JSONL lines stay valid since only the string content is
# replaced). Writes via tmp+os.replace, so it works on 0400/read-only files.
#
# Safety:
#   * --dry-run prints what would change, touches nothing.
#   * files modified in the last 5 minutes are skipped (may belong to a live
#     agent session still writing).
#   * findings whose Secret is <8 bytes are skipped (too risky to splice).
#
# After scrubbing, cass picks up the changed files on its next incremental
# index; originals may still sit in cass's raw-mirror dir — scan that too
# (the default target list includes it).
#
# Usage:
#   scrub-transcripts.sh --dry-run              # preview
#   scrub-transcripts.sh                        # scrub default transcript dirs
#   scrub-transcripts.sh DIR [DIR...]           # scrub specific dirs/files
#
set -euo pipefail

DRY=0
[ "${1-}" = "--dry-run" ] && { DRY=1; shift; }

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
fi

targets=()
for t in "$@"; do [ -e "$t" ] && targets+=("$t"); done
[ "${#targets[@]}" -gt 0 ] || { echo "no transcript dirs exist" >&2; exit 1; }

gitleaks dir --config "$CONF" --no-banner --exit-code 0 \
  --report-format json --report-path "$REPORT" "${targets[@]}"

python3 - "$REPORT" "$DRY" <<'EOF'
import json, sys, os, time

report, dry = sys.argv[1], sys.argv[2] == "1"
findings = json.load(open(report)) if os.path.getsize(report) else []
now = time.time()
by_file = {}
skipped_recent = skipped_short = 0

for f in findings:
    path = f["File"]
    if now - os.path.getmtime(path) < 300:
        skipped_recent += 1
        continue
    if len(f["Secret"].encode()) < 8:
        skipped_short += 1
        continue
    by_file.setdefault(path, []).append(f)

changed = 0
for path, hits in sorted(by_file.items()):
    with open(path, "rb") as fh:
        content = fh.read()
    n = 0
    # Replace the literal secret value wherever it occurs in the file —
    # safer than column offsets (encoding edge cases) and catches repeats.
    for h in hits:
        secret = h["Secret"].encode()
        rep = f"[REDACTED:{h['RuleID']}]".encode()
        if secret in content:
            content = content.replace(secret, rep)
            n += 1
    if n == 0:
        continue
    if dry:
        print(f"dry-run  {n:3d}  {os.path.relpath(path, os.path.expanduser('~'))}")
    else:
        tmp = path + ".scrub.tmp"
        with open(tmp, "wb") as fh:
            fh.write(content)
        os.chmod(tmp, os.stat(path).st_mode & 0o777)
        os.replace(tmp, path)
        print(f"scrubbed {n:3d}  {os.path.relpath(path, os.path.expanduser('~'))}")
    changed += n

print(f"\n{changed} secrets {'would be ' if dry else ''}redacted in {len(by_file)} files")
if skipped_recent:
    print(f"skipped {skipped_recent} findings: file modified <5min ago (live session?)")
if skipped_short:
    print(f"skipped {skipped_short} findings: secret shorter than 8 bytes")
EOF
