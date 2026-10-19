---
name: logseq-add-md-to-blocks
description: Import a Markdown file (or notes written from the current conversation) into a Logseq DB graph as a nested block tree (headings, paragraphs, list items, tables, code) under a target block or page, via the logseq CLI.
allowed_tools:
  - Bash
  - Read
user_invocable: true
---
The user gives a destination: a block (`[[<uuid>]]` or a uuid), or a page name. Usually also a Markdown file; without one ("document this here"), you write the Markdown yourself from the conversation. Optionally a graph name.

## Steps

1. **Pick the graph.** If the user named one, use it. Otherwise (no graph named, or "current graph"), run `logseq server list` and use the graph whose `owner-source` is `electron` (the one open in the desktop app). Only ask if there's more than one such graph, or none.

2. **Check the target exists:** `logseq show -g <graph> --uuid <uuid>` (or `--id`). The output lists the target's ancestors first, as `>` breadcrumb lines, then the target itself (no `>`), then its children as a tree; the target is the last line before the tree, not the first. Add `--output json` if it's unclear (`data.root` is the target). For a page target, `logseq list page -g <graph>` / `logseq search page`. Note the target's title, its ancestors and any existing children: they tell you where new blocks will land and what the content should cover.

3. **Write the input** (skip if the user gave a file). Save it as `/tmp/logseq-md-to-blocks/input.md` (`mkdir -p /tmp/logseq-md-to-blocks` first).

   Fit it to the target: the target's title is already the heading, so don't open with a heading or block that repeats it (under a block titled "Hiding them", start with the how-to, not a `## How to hide them` heading). Put the content the title asks for first, and background after it.

   When the content comes from the conversation, re-check each claim before writing it down, especially config keys, flags, paths and anything that was a guess or recalled from memory: check the current docs, `--help`, or the files themselves. Notes outlive the conversation, so a wrong claim does more damage there. If re-checking shows something you told the user was wrong, say so in your report.

   Write every link as a Markdown link whose text is the target's own title, not a bare URL: the issue or PR title for an issue or PR, the repo name for a repo, the page title for anything else, without the site-name suffix (`Policies | OpenCode` → `Policies`, `Models.dev - An open-source database of AI models` → `Models.dev`). Look titles up rather than paraphrasing them, e.g. `gh issue view N -R owner/repo --json title -q .title` (`gh pr view` for PRs). Put your own notes (why it matters, how it relates) after the link. With `--gfw`, don't write anything the widget already shows: no open/closed/merged state, and for repos no stars, last-commit age or issue/PR counts. For example: `- [Plan mode in chat UI](https://github.com/stablyai/orca/issues/11548) — user request from Discord`. Refer to issues and PRs as "PR 123" or "issue 123", never `#123`, which Logseq turns into a tag. Titles need two fixes before they go in link text: drop issue-template prefixes like `[Feature]:` or `[Bug]:` (a `]` inside the link text stops `--gfw` from recognising the link, and a leading `[[` becomes a page link), and escape any `#` in the title as `\#`.

4. **Convert** the Markdown into a block outline:
   ```
   mkdir -p /tmp/logseq-md-to-blocks
   ~/Projects/installs/scripts/logseq-md-to-blocks.py <input.md> /tmp/logseq-md-to-blocks/blocks.md
   ```
   Headings become parent blocks (nested by level). Paragraphs and list items become one block each. Tables and code fences stay whole as one block. A list, table or code block after a paragraph ending in ":" nests under it. Skim the output (`cut -c1-110`) and check that the structure looks right.

   Add `--gfw` (before the input path) to give every block that *starts with* a GitHub link a live Git Forge Watcher widget (`{{renderer :gfw, <encoded-url>}}`; plugin source in `~/Projects/Git/Categories/Logseq-ALL/logseq-plugin-git-forge-watcher`). For a repo link the macro goes on the block's second line. For an issue, pull request or branch link (`/issues/N`, `/pull/N`, `/tree/<branch>`) it goes at the start of the first line (after any heading `#`s), with one space before the rest of the block. Use it whenever the blocks are about GitHub repos, issues or PRs.

   Append a final top-level block identifying the session that wrote the notes — one line, the whole thing in backticks. If `$ORCA_TAB_ID` is set (running in an Orca tab), use the tab id:
   ```
   [ -n "$ORCA_TAB_ID" ] && printf -- '- `orcaTabId: %s`\n' "$ORCA_TAB_ID" >> /tmp/logseq-md-to-blocks/blocks.md
   ```
   That produces `` `orcaTabId: 2e8c58c3-f010-4b37-84ce-bb6d9ebdb3ea` ``. If it's unset (not running under Orca), use your own agent session id with the `agentSessionID` key instead, e.g. `` `agentSessionID: sudsy-shingle` ``. For Devin, read it from the session locks: each `~/.local/share/devin/cli/session_locks/<session-id>.lock` holds the PID of the `devin acp` process that owns the session, and tool shells are its descendants, so the id is the lock filename matching an ancestor PID:
   ```
   pid=$PPID; f=
   while [ "$pid" -gt 1 ] && [ -z "$f" ]; do
     f=$(grep -l "^${pid}$" ~/.local/share/devin/cli/session_locks/*.lock 2>/dev/null | head -1)
     pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
   done
   [ -n "$f" ] && printf -- '- `agentSessionID: %s`\n' "$(basename "$f" .lock)" >> /tmp/logseq-md-to-blocks/blocks.md
   ```
   For Claude Code, the UUID of the current `~/.claude/projects/<dir>/*.jsonl` transcript. Skip the block only when no id can be determined.

5. **Check for side effects.** `[[...]]` and `#tag` in the text create or link pages in Logseq. Run a dry run and check `would-create-pages`:
   ```
   logseq upsert block -g <graph> --target-uuid <uuid> --pos last-child --dry-run --output json --blocks-file /tmp/logseq-md-to-blocks/blocks.md \
     | python3 -c 'import json,sys;d=json.load(sys.stdin)["data"];print(len(d["ops"][0][1][0]), "blocks;", "new pages:", d["would-create-pages"])'
   ```
   If unexpected pages would be created, tell the user before writing. Use `--target-page "<name>"` instead of `--target-uuid` for a page target.

6. **Write:** run the same command without `--dry-run` and `--output json`. It prints the new block ids and `Count: N`.

7. **Verify.** `logseq show` on the target can fail with `Failure(fetch failed)` for large trees. If so, verify with a query instead, and `show --id` a few of the section subtrees:
   ```
   logseq query -g <graph> --query '[:find (count ?c) :where [?p :block/uuid #uuid "<uuid>"] [?c :block/parent ?p]]'
   ```

8. Report the graph, the target, the block count, and anything that didn't verify.
