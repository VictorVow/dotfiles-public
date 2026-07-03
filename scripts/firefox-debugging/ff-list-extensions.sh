#!/usr/bin/env bash
# List a profile's extensions: name, id, version, state, last update time.
# Sorted newest-updated first — after a mystery regression, the recently
# updated ones are the prime suspects (staged updates activate at the next
# browser restart, so breakage can appear days after the update downloaded).
#
# Usage: ff-list-extensions.sh [-p PROFILE] [-a]   (-a includes disabled)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; source ./ff-lib.sh

PROFILE=VERTEX ALL=0
while getopts "p:ah" o; do case $o in
  p) PROFILE=$OPTARG;; a) ALL=1;;
  h) grep '^#' "$0" | head -7; exit 0;;
esac; done
DIR=$(ff_profile_dir "$PROFILE")

python3 - "$DIR/extensions.json" "$ALL" <<'EOF'
import datetime, json, sys
data = json.load(open(sys.argv[1]))
show_all = sys.argv[2] == "1"
rows = []
for a in data.get("addons", []):
    if a.get("type") != "extension":
        continue
    if not a.get("active") and not show_all:
        continue
    updated = a.get("updateDate") or a.get("installDate") or 0
    rows.append((updated, (a.get("defaultLocale") or {}).get("name", "?"),
                 a.get("id"), a.get("version"), a.get("active")))
rows.sort(reverse=True)
for updated, name, ext_id, version, active in rows:
    when = datetime.datetime.fromtimestamp(updated / 1000).strftime("%Y-%m-%d %H:%M")
    state = "active" if active else "DISABLED"
    print(f"{when}  {state:8s}  {name:45.45s}  {version:12.12s}  {ext_id}")
EOF
