---
name: logseq-comparisons-update
description: Fill out an "X vs Y" comparison block in the user's Logseq graph. Reads the user's notes on both options (block refs or plain text), researches them, and writes advantages under each "For X" / "For Y" child plus the "Similarities" and "Unclear" children, using block references to existing notes.
allowed-tools: Bash Read Write WebSearch WebFetch
compatibility: "Requires the logseq CLI and a running Logseq DB graph"

---
The user points at a comparison block (`[[<uuid>]]`) in their Logseq graph. It compares two things, and it usually looks like this:

```
<A> vs <B>
├── For <A>
│   └── (empty)
├── For <B>
│   └── (empty)
├── Similarities
│   └── (empty)
└── Unclear
    └── (empty)
```

`<A>` and `<B>` can each be a **block reference** (`[[<uuid>]]`, shown resolved in `logseq show`) or **plain text**. The comparison often sits under one option's `Pros/Cons > Comparisons` block.

Uses the `logseq` CLI. See the `logseq-cli` skill for command details. The tree helper `logseq-tree.py` is shared from the `logseq-add-md-to-blocks` skill: `~/.claude/skills/logseq-add-md-to-blocks/scripts/logseq-tree.py` (written as `logseq-tree.py` below).

## Steps

### 1. Find the graph and the comparison block

- Graph: `logseq server list` → the graph whose `owner-source` is `electron` (usually `logseq-apex`).
- Dump the comparison block's subtree with `logseq-tree.py <graph> <uuid>`. It prints `[db-id uuid] title` per block, with refs left as raw `[[uuid]]`. `logseq show` fails ("fetch failed") on blocks whose breadcrumb contains a `{{renderer :gfw …}}` macro, so use the script when that happens.
- Note the db/ids of `For <A>`, `For <B>`, `Similarities` and `Unclear`, and whether each has only an empty placeholder child or already has content. Keep existing content and add to it; don't overwrite it.
- Read the ancestors as well (`logseq show --uuid` prints the breadcrumb). If the comparison sits under one option's Pros/Cons, read that option's Pros, Cons and Unclear too. They are the user's main notes on it.

### 2. Read the user's notes on each side

For a **block reference**:
- Resolve it: `logseq query -g <graph> --query '[:find ?id ?t :in $ ?u :where [?b :block/uuid ?u] [?b :block/title ?t] [(identity ?b) ?id]]' --inputs '[#uuid "<uuid>"]'`.
- Dump its whole subtree with `logseq-tree.py`, and look at its **linked references** (`logseq show --id <id>` lists them when it works). Journal entries and other pages often record how the user actually uses it.
- Follow every `[[uuid]]` inside those blocks one level further (resolve with the query above). Refs that point to a tool or a concept, like the ACP block or an "Orca native chat" section, usually hold the most useful context.

For **plain text**:
- Search the graph: `logseq search block -g <graph> --content "<text>"`, plus any short names or aliases. Then find the parents of the hits: `logseq query -g <graph> --query '[:find (pull ?b [:db/id :block/title {:block/parent [:db/id :block/title {:block/parent [:db/id :block/title]}]}]) :in $ ?b]' --inputs '[<id>]'`. Dump the relevant section with `logseq-tree.py`.
- If the graph has nothing on it, rely on research, and say so in the final report.

Work out *why* the user is comparing these two things, e.g. "the same agent in Zed (via ACP) vs Orca (via SDK)". Frame the advantages for that real choice, not in general.

### 3. Research

The user wants your own research too, not just a summary of their blocks.
- Use the GitHub API for repo facts: `gh api repos/<o>/<r> --jq '{desc:.description,lic:.license.spdx_id,pushed:.pushed_at}'`, the README (`gh api repos/<o>/<r>/readme --jq .content | base64 -d`), docs files, `gh release list -R <o>/<r>`, and dependency versions in `package.json` and the like.
- Get official docs as Markdown when the site offers it (e.g. `curl -sL https://code.claude.com/docs/en/<page>.md`). Check package registries for the latest versions (`npm view <pkg> version`).
- Look for concrete, checkable differences: version lag, release cadence, license, who maintains it, which clients or hosts support it, features one side has and the other lacks, and limits they share.
- Mark claims you couldn't verify as such ("unverified", or put them under Unclear).

### 4. Write the blocks

Format (settled 2026-10-17):
- **For `<A>` / For `<B>`**: one block per advantage of that option over the other. Lead with the advantage, then a short reason or concrete example, in one or two sentences. Use concrete numbers where you have them (versions, dates, counts of modes).
- **Similarities**: what both share, including shared limitations. Point out when one side's "cons" are really shared, e.g. a gap in a common upstream.
- **Unclear**: open questions, unverified points, and things that depend on future upstream decisions.
- **Block references**: when an existing block supports a point, add it as a **child block** containing just `[[<uuid>]]`, so it renders as an embedded ref under the point. A ref can also go inline when it names a thing, e.g. `Works in any [[<ACP block uuid>]] client`. Reference the most specific block, e.g. the exact "Codex chats get only Ask / …" bullet rather than its section.
- Use `[[uuid]]` refs only. Don't write `[[Page Name]]` links or `#tags`, since they create pages. No hard wrapping. Don't add headings.

Write one Markdown file per section, e.g. `/tmp/logseq-comparisons/for-a.md`:
```
- First advantage …
  - [[<supporting-block-uuid>]]
- Second advantage …
```
Then import each one under its section block:
```
logseq upsert block -g <graph> --target-id <section-db-id> --pos last-child --blocks-file /tmp/logseq-comparisons/for-a.md -o json
```
Known behaviour (CLI as of 2026-10-19, source checked at `399025dc50`):
- If the section's **last** child is an empty block and the file has **2+ blocks in total** (children count, since the CLI sends one flattened insert), the first new block **fills that empty block** (taking over its uuid) and the rest become its siblings. With a single-block file the empty placeholder is *not* filled and stays behind, so remove it afterwards.
- In exactly that placeholder-fill case the command returns `{"status":"error","error":{"code":"add-id-resolution-failed",…}}` even though every block was written. Cause: `--pos last-child` makes the outliner retarget to the last child as a sibling and auto-enable `replace-empty-target?` (`deps/outliner/src/logseq/outliner/core.cljs`, `get-target-block` / `insert-blocks`), so the first block gets the placeholder's uuid; the CLI then looks up the uuid *it* generated for that block (`cli/lib/add.ml`, `resolve_created_ids`), finds nothing, and fails. Always verify instead of retrying, since a retry duplicates the blocks. Sections without an empty last child return `ok` with the ids.

### 5. Verify

- `logseq-tree.py <graph> <comparison-uuid>`: check every section, look for duplicates and confirm no empty blocks remain.
- Check that refs resolved to real references (not plain text): `logseq query -g <graph> --query '[:find (pull ?b [:db/id {:block/refs [:db/id]}]) :in $ [?b ...]]' --inputs '[[<id1> <id2>]]'`.
- Report a short summary of each section to the user, say what came from research and what from their notes, and list anything inferred rather than verified. Mention the spurious CLI error if it happened.

### 6. Record new choices

If the user changes the format or corrects the approach, update this file (`~/Projects/installs/nix/dotfiles/agent-skills/logseq-comparisons-update/SKILL.md`) and tell them to run `hms`.
