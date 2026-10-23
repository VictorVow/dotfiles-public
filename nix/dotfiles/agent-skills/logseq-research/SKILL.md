---
name: logseq-research
description: Research a topic (usually "what tools/options exist for X") and write the result as a formatted research outline under a block in the user's Logseq graph, building on the user's existing notes there. Imports via `logseq-add-md-to-blocks`. Iterate on formatting until the user is happy.
allowed-tools: Bash Read Write WebSearch WebFetch
compatibility: "Requires the logseq CLI and a running Logseq DB graph"

---
The user points at a Logseq block (`[[<uuid>]]`) whose children hold their own notes on a topic, usually a list of tools, and names a child block (often "Claude research") to put your research under.

Uses the `logseq` CLI. See the `logseq-cli` skill for command details. Import mechanics (graph selection, convert, dry-run, write, verify, session-ID block, `--gfw`) live in `logseq-add-md-to-blocks` — follow that skill for the actual write, not this one. The bundled helper is `scripts/logseq-clear-children.sh`.

## Steps

Create a task list with these four tasks and keep it updated:
1. Do the research
2. Add it into Logseq
3. Iterate on formatting until the user is happy (they may delete everything and ask for a re-add in a different format)
4. Update this skill/scripts with any new formatting choices

### 1. Read the user's existing notes first

- Graph: `logseq server list` → the graph whose `owner-source` is `electron`.
- Read the **whole** subtree of the topic block, not just the first level: `logseq show -g <graph> --uuid <uuid>`. Also dump it with `--output json` to see properties (headings, collapsed, assets). Look at any image assets (`~/logseq/graphs/<graph>/assets/<asset-uuid>.png`, uuid from a `:logseq.property.asset/checksum` query) with Read.
- Find the target block's uuid with a query on `:block/title`. Note whether it already has children.
- The user's existing groupings are a best guess, not a rule. Use whatever structure makes the most sense; overlapping theirs is fine.

### 2. Research

- Cover every tool the user already listed, plus notable ones they missed. Mark the missed ones with "(new)" in their heading.
- Use the GitHub API rather than web pages for repo facts: `gh api repos/<owner>/<repo> --jq '[.full_name,.stargazers_count,.pushed_at[:10],.license.spdx_id,.language,.description]|@tsv'`. Read READMEs with `gh api repos/<o>/<r>/readme --jq .content | base64 -d`. Use these numbers to *judge* activity and maturity, but don't write star counts or activity into the doc (the widget shows them).
- Check nixpkgs availability (`nix eval --raw nixpkgs#<pkg>.version`), and check what's already installed in `~/Projects/installs` (`rg` in `nix/modules/`). Write recommendations for the user's actual setup: Kubuntu/KDE, Claude Code + Codex + OpenCode, Zed, GitHub + self-hosted Forgejo.
- Mark unverified claims as such. Vendor benchmarks are vendor benchmarks.

### 3. Write the Markdown, using the house format

Write to `/tmp/logseq-research/<topic>.md`. The user settled on this format (2026-10-16):

- **No H1 title.** The target block is the title. Start with one intro paragraph: `Claude research, <date>.`, how the doc is organised, a note that GitHub stats are live in the widgets, and what "(new)" means.
- **H2 (`##`) for sections.** Typically: `TL;DR for this setup` first, then numbered sections (`## 1. …`) ordered by the workflow, then `Practical habits…` (optional), and `Sources` last.
- **H3 (`###`) for each tool or option** within a section. The heading is just the link: `### [name](https://github.com/owner/repo)`, plus ` (new)` if the user hadn't listed it. Non-tool items (e.g. "Claude Code built-ins", "Others", "Stacked PRs") get plain-text H3s too. Sources gets H3 subgroups (`Primary`, `Comparisons and articles`).
- **First child of a tool H3: a one-line fact summary** as a paragraph: license, language, nixpkgs status and package name, oddities (e.g. "MIT, Rust, in nixpkgs (`tuicr`).", "Beta.", "No clear license."). **No star counts, no "active / quiet since" text**, because the Git Forge Watcher widget shows stars, last-commit age and open issues/PRs live.
- **Then bullets** with what it does, how it fits the user's workflow, and caveats. Keep each bullet to one or two sentences. A tool that appears in two sections gets a short "See section N." entry the second time.
- Each H2 section opens with a one-sentence paragraph saying what the section covers.
- The TL;DR is plain bullets with **bold** tool names and no links.
- No `[[page links]]` or `#tags` in the text (they create pages). No hard wrapping.

### 4. Convert and import

Follow `logseq-add-md-to-blocks` steps 4-8 with these specifics:

- Input file: `/tmp/logseq-research/<topic>.md`; output `/tmp/logseq-research/blocks.md`
- Always pass `--gfw` — the user requires the Git Forge Watcher widget on every standalone GitHub-repo block. Check with `grep -c 'renderer :gfw' blocks.md` (should equal the number of GitHub tool headings).
- Target: the named child block, `--pos last-child`
- On verify: in Logseq the stored title loses the `###` — it becomes `:logseq.property/heading 3`, and the widget macro sits on the title's second line.

### 5. Formatting loop

Report the outcome and the current formatting choices, and ask for changes. If the user wants a new format:
- If they say they deleted the blocks, confirm the target has 0 children (the count query above).
- If they ask *you* to delete them: `scripts/logseq-clear-children.sh --dry-run <graph> <target>` first, check that the titles are yours (the user may have edited blocks in that subtree, which is expected), then run it without `--dry-run`.
- Edit the Markdown, re-convert, dry-run, write, verify. Look at any blocks the user edited by hand (`logseq show --uuid`); they show the format they want.

### 6. Record new formatting choices

Once the user calls the format final, update this skill's "house format" section (`~/Projects/installs/nix/dotfiles/agent-skills/logseq-research/SKILL.md`) and the scripts with anything new, then tell the user to run `hms`.
