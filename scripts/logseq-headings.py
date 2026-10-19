#!/usr/bin/env python3
"""logseq-headings.py — re-level the headings in a Logseq block subtree.

Usage: logseq-headings.py <graph> <root-db-id> [--root-level N] [--shift N] [--max-level N] [--dry-run]

Sets the root block's heading to --root-level (if given), adds --shift to the
heading level of every heading block below it (negative = bigger), and clamps
the result to 1..--max-level (the smallest heading allowed, default 6). Prints
each heading block as `<db/id> <old> -> <new> <title>`.

logseq-md-to-blocks.py nests blocks by Markdown heading level, so a subtree
whose child headings should be the same size as (or bigger than) their parent
has to be written with deeper `#`s and re-levelled afterwards with this.
Used by the hn-favorites-digest skill.
"""
import argparse
import json
import subprocess
import sys

# Every block on the root's page in one query; the subtree is walked in Python
# (one `logseq query` per block takes minutes on a few hundred blocks).
PAGE_BLOCKS = (
    "[:find (pull ?b [:db/id :block/title :logseq.property/heading {:block/parent [:db/id]}]) "
    ":in $ ?r :where [?r :block/page ?p] [?b :block/page ?p]]"
)
HEADING = "[:find ?h :in $ ?b :where [?b :logseq.property/heading ?h]]"


def query(graph, q, inputs):
    r = subprocess.run(
        ["logseq", "query", "-g", graph, "--query", q, "--inputs", inputs, "-o", "json"],
        capture_output=True, text=True,
    )
    d = json.loads(r.stdout)
    if d.get("status") != "ok":
        sys.exit(f"query failed: {d.get('error')}")
    return d["data"]["result"]


def set_heading(graph, eid, level):
    r = subprocess.run(
        ["logseq", "upsert", "block", "-g", graph, "--id", str(eid),
         "--update-properties", f"{{:logseq.property/heading {level}}}"],
        capture_output=True, text=True,
    )
    if r.returncode:
        sys.exit(f"failed to set heading on {eid}: {r.stdout}{r.stderr}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("graph")
    p.add_argument("root", type=int)
    p.add_argument("--root-level", type=int)
    p.add_argument("--shift", type=int, default=0)
    p.add_argument("--max-level", type=int, default=6)
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()

    changes = []
    if a.root_level:
        old = query(a.graph, HEADING, f"[{a.root}]")
        old = old[0] if old else None
        old = old[0] if isinstance(old, list) else old
        changes.append((a.root, old, a.root_level, "(root)"))
    kids = {}
    for (b,) in query(a.graph, PAGE_BLOCKS, f"[{a.root}]"):
        kids.setdefault((b.get("block/parent") or {}).get("db/id"), []).append(b)
    todo = [a.root]
    while todo:
        for b in kids.get(todo.pop(), []):
            todo.append(b["db/id"])
            h = b.get("logseq.property/heading")
            if h:
                new = min(max(h + a.shift, 1), a.max_level)
                changes.append((b["db/id"], h, new, b.get("block/title", "")[:60]))

    for eid, old, new, title in sorted(changes):
        if old != new and not a.dry_run:
            set_heading(a.graph, eid, new)
        print(f"{eid}\t{old} -> {new}\t{title}")


if __name__ == "__main__":
    main()
