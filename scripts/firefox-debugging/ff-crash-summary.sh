#!/usr/bin/env bash
# Summarize recent Firefox crash dumps (the .extra metadata next to each .dmp).
# Shows process type, crash reason, and the URL annotation — for extension-process
# crashes the URL names an extension page loaded in that process (suggestive, but
# NOT proof of guilt: all extensions share one process).
#
# Usage: ff-crash-summary.sh [-n COUNT]
set -euo pipefail
PENDING="$HOME/.mozilla/firefox/Crash Reports/pending"
COUNT=5
while getopts "n:h" o; do case $o in
  n) COUNT=$OPTARG;; h) grep '^#' "$0" | head -7; exit 0;;
esac; done

[[ -d $PENDING ]] || { echo "no pending crash reports dir"; exit 0; }
ls -t "$PENDING"/*.extra 2>/dev/null | head -"$COUNT" | while read -r extra; do
  echo "== $(basename "$extra" .extra)  ($(date -r "$extra" '+%F %T')) =="
  python3 - "$extra" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
keys = ["ProcessType", "RemoteType", "MozCrashReason", "CrashReason", "URL",
        "Version", "BuildID", "JSOutOfMemory", "OOMAllocationSize",
        "TotalPhysicalMemory", "AvailablePhysicalMemory"]
for k in keys:
    if k in d:
        print(f"  {k}: {str(d[k])[:140]}")
EOF
done
