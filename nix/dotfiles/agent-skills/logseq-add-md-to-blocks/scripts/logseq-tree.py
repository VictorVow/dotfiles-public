#!/usr/bin/env python3
"""logseq-tree.py — print a block's subtree with db/ids, uuids and full titles.

Usage: logseq-tree.py <graph> <block-uuid|db-id> [max-depth]

`logseq show` fails ("fetch failed") on some blocks, e.g. ones whose breadcrumb
contains a {{renderer :gfw ...}} macro, so this walks the tree with queries
instead. Children are sorted by :block/order. Newlines in titles print as " ⏎ ".
Shared by the logseq-comparisons-update and logseq-enrich-blocks skills.
"""
import json
import subprocess
import sys

CHILDREN = (
    "[:find (pull ?b [:db/id :block/uuid :block/title :block/order]) "
    ":in $ ?p :where [?b :block/parent ?p]]"
)
BY_UUID = "[:find ?b :in $ ?u :where [?b :block/uuid ?u]]"


def query(graph, q, inputs):
    r = subprocess.run(
        ["logseq", "query", "-g", graph, "--query", q, "--inputs", inputs, "-o", "json"],
        capture_output=True, text=True,
    )
    d = json.loads(r.stdout)
    if d.get("status") != "ok":
        sys.exit(f"query failed: {d.get('error')}")
    return d["data"]["result"]


def walk(graph, eid, depth, max_depth):
    if depth > max_depth:
        return
    kids = sorted((row[0] for row in query(graph, CHILDREN, f"[{eid}]")),
                  key=lambda b: b.get("block/order", ""))
    for b in kids:
        title = b.get("block/title", "").replace("\n", " ⏎ ")
        print("  " * depth + f"- [{b['db/id']} {b.get('block/uuid', '')}] {title}")
        walk(graph, b["db/id"], depth + 1, max_depth)


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__.split("\n\n")[1])
    graph, target = sys.argv[1], sys.argv[2]
    max_depth = int(sys.argv[3]) if len(sys.argv) == 4 else 20
    if target.isdigit():
        eid = int(target)
    else:
        rows = query(graph, BY_UUID, f'[#uuid "{target}"]')
        if not rows:
            sys.exit(f"no block with uuid {target}")
        eid = rows[0][0]
    walk(graph, eid, 0, max_depth)


if __name__ == "__main__":
    main()
