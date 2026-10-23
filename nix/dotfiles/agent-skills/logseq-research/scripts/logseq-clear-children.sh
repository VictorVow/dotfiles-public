#!/usr/bin/env bash
# logseq-clear-children.sh — remove every child block (and their subtrees) under
# one block in a Logseq DB graph, leaving the block itself in place.
#
# Usage: logseq-clear-children.sh [--dry-run] <graph> <block-uuid>
#
# Used by the logseq-research skill to wipe a research block before re-adding it
# in a different format. Prints the children's titles first; --dry-run stops there.
set -euo pipefail

dry=0
if [[ ${1:-} == --dry-run ]]; then dry=1; shift; fi
[[ $# -eq 2 ]] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
graph=$1 uuid=$2

children_query="[:find ?c ?t :where [?p :block/uuid #uuid \"$uuid\"] [?c :block/parent ?p] [?c :block/title ?t]]"
count_query="[:find (count ?c) :where [?p :block/uuid #uuid \"$uuid\"] [?c :block/parent ?p]]"

rows=$(logseq query -g "$graph" --output json --query "$children_query")
ids=$(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
d = d.get("data", d)
rows = d.get("result", d) if isinstance(d, dict) else d
for _, title in rows:
    print("  " + title.split("\n")[0][:100], file=sys.stderr)
print(json.dumps([r[0] for r in rows]).replace(" ", ""))
' "$rows")

if [[ $ids == "[]" ]]; then echo "No children under $uuid."; exit 0; fi
echo "Children of $uuid: $ids"
(( dry )) && exit 0

logseq remove block -g "$graph" --id "$ids" >/dev/null
left=$(logseq query -g "$graph" --query "$count_query")
if [[ -n $left && $left != "[0]" ]]; then
  echo "Some children remain: $left" >&2; exit 1
fi
echo "Removed. $uuid now has no children."
