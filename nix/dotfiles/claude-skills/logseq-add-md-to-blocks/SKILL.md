---
name: logseq-add-md-to-blocks
description: Import a Markdown file into a Logseq DB graph as a nested block tree (headings, paragraphs, list items, tables, code) under a target block or page, via the logseq CLI.
allowed_tools:
  - Bash
  - Read
user_invocable: true
---
The user gives a Markdown file and a destination: a block (`[[<uuid>]]` or a uuid), or a page name. Optionally a graph name.

## Steps

1. **Pick the graph.** If the user named one, use it. If they said "current graph", run `logseq server list` and use the graph whose `owner-source` is `electron` (the one open in the desktop app). If that's ambiguous, ask.

2. **Check the target exists:** `logseq show -g <graph> --uuid <uuid>` (or `--id`). For a page target, `logseq list page -g <graph>` / `logseq search page`. Note any existing children so you know where new blocks will land.

3. **Convert** the Markdown into a block outline:
   ```
   mkdir -p /tmp/logseq-md-to-blocks
   ~/Projects/installs/scripts/logseq-md-to-blocks.py <input.md> /tmp/logseq-md-to-blocks/blocks.md
   ```
   Headings become parent blocks (nested by level). Paragraphs and list items become one block each. Tables and code fences stay whole as one block. A list, table or code block after a paragraph ending in ":" nests under it. Skim the output (`cut -c1-110`) and check that the structure looks right.

   Add `--gfw` (before the input path) to give every block that *starts with* a GitHub link a live Git Forge Watcher widget (`{{renderer :gfw, <encoded-url>}}`; plugin source in `~/Projects/Git/Categories/Logseq-ALL/logseq-plugin-git-forge-watcher`). For a repo link the macro goes on the block's second line. For an issue, pull request or branch link (`/issues/N`, `/pull/N`, `/tree/<branch>`) it goes at the start of the first line (after any heading `#`s), with one space before the rest of the block. Use it whenever the blocks are about GitHub repos, issues or PRs.

4. **Check for side effects.** `[[...]]` and `#tag` in the text create or link pages in Logseq. Run a dry run and check `would-create-pages`:
   ```
   logseq upsert block -g <graph> --target-uuid <uuid> --pos last-child --dry-run --output json --blocks-file /tmp/logseq-md-to-blocks/blocks.md \
     | python3 -c 'import json,sys;d=json.load(sys.stdin)["data"];print(len(d["ops"][0][1][0]), "blocks;", "new pages:", d["would-create-pages"])'
   ```
   If unexpected pages would be created, tell the user before writing. Use `--target-page "<name>"` instead of `--target-uuid` for a page target.

5. **Write:** run the same command without `--dry-run` and `--output json`. It prints the new block ids and `Count: N`.

6. **Verify.** `logseq show` on the target can fail with `Failure(fetch failed)` for large trees. If so, verify with a query instead, and `show --id` a few of the section subtrees:
   ```
   logseq query -g <graph> --query '[:find (count ?c) :where [?p :block/uuid #uuid "<uuid>"] [?c :block/parent ?p]]'
   ```

7. Report the graph, the target, the block count, and anything that didn't verify.
