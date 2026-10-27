---
name: logseq-enrich-blocks
description: Tidy the children of a Logseq block in place, given its block id (e.g. `[[6adfc842-…]]`) — usually an inbox of saved Markdown links. Groups related children under H3 heading blocks (and related H3s under H2s), cleans link text and adds Git Forge Watcher (gfw) widgets the way `logseq-add-md-to-blocks` does, and under each link adds a "Related:" block with block refs to related notes elsewhere in the graph. Moves blocks rather than re-creating them, so uuids and refs survive.
allowed-tools: Bash Read Write
compatibility: "Requires the logseq CLI and a running Logseq DB graph"

---
The user gives a block (`[[<uuid>]]` or a uuid), optionally a graph. You work on all of its children; the block itself is left alone.

The bundled script is `scripts/logseq-enrich.py` (`dump`, `index`, `related`, `apply`; run it without arguments for usage). It shares its link rules with `logseq-add-md-to-blocks` through that skill's `scripts/logseq_links.py`, and the tree printer `logseq-tree.py` lives there too (`~/.claude/skills/logseq-add-md-to-blocks/scripts/logseq-tree.py`). Scratch files go to `/tmp/logseq-enrich/<root-uuid>/`.

## Steps

1. **Load `logseq-add-md-to-blocks`** with the Skill tool, once, at the start. Its rules for link text, `--gfw` placement, page-creating `[[...]]`/`#tags` and the session-id block apply here; if anything below disagrees with it, that skill wins. Use its steps 1–2 to pick the graph and check the target.

2. **Read the children:** `scripts/logseq-enrich.py dump <graph> <uuid>`. It prints every block's db-id, its link text after cleaning, the URL, `gfw` if it will get a widget, `retitle` if its link text will change, and existing `related=N` refs. Headings from an earlier run are shown with their blocks (`[in: …]`); keep them and add to them. Where a title alone doesn't tell you what a link is, look it up (`gh api repos/<o>/<r> --jq .description` for GitHub repos).

   Check the cleaned link text (add-md step 3 rules). Where it's still wrong (a leftover site name, a title that's just "Error" or "Introduction"), put the right text in the plan's `titles`.

3. **Group.** Plan H3 headings for blocks that share a clear topic (a tool category, a game, a project, a subject); give an H3 two or more blocks, and don't force a block into a group it doesn't fit. Where two or more H3s share a broader topic, put them under an H2. Headings are short plain text: no links, no `[[...]]`, no `#`. Blocks that don't fit anywhere stay ungrouped and end up after the headings, in their original order.

4. **Find related blocks:** `scripts/logseq-enrich.py index <graph>` (one ~20 s query of every block, cached for a day; `--refresh` after big graph edits), then `scripts/logseq-enrich.py related <graph> <uuid>`. For each link block it lists up to 6 candidates from outside the root's subtree (and outside other `Related:` blocks), each with score, uuid, why it matched (`url`/`repo`/`reddit`/`hn` = same page, repo or post; otherwise the shared words), its page › parent, and its title. Pass `--top=N` for more.

   The list is only candidates: keyword matches are often coincidences. Keep a candidate only if it's genuinely about the same thing: the same tool, repo, post or product, or the user's notes on that topic. Prefer the most specific block, e.g. the note about the tool rather than the section above it; read a candidate's subtree with `logseq-tree.py <graph> <uuid> 2` when you're unsure. Usually 0–3 per link; many links will have none.

5. **Write the plan** to `/tmp/logseq-enrich/<uuid>/plan.json` (format in the script's docstring: `groups` of `h2` + `h3` lists with db-ids, `ungrouped`, `related` mapping link db-id → uuids, optional `titles`). Then **show the user** a readable outline and **wait for their OK** before writing anything:
   ```
   ## AI coding
   ### Orchestrators
   - paseo — Related: "paseo" in Agentic Productivity › Resources
   ### Kingdom Come mods
   - …
   Ungrouped: Your Operator, …
   Retitled: <old> → <new> (only where you overrode or it isn't obvious)
   ```
   Apply any changes they ask for to the plan.

6. **Write.** `scripts/logseq-enrich.py apply <plan.json> --dry-run` first: check the ops and that `would-create-pages` is `[]`. Then run it without `--dry-run`. It creates missing headings, moves blocks (`upsert block --id … --target-id …`, which keeps uuids and children), rewrites link text and adds gfw widgets, and adds `Related:` children with one `[[uuid]]` per block. It's idempotent: on a rerun it reuses headings by title, skips blocks already in place and refs already present. If an op fails it says `FAILED:` and carries on; fix and rerun rather than undoing.

   Then add the session-id block (add-md step 4: `orcaTabId` or `agentSessionID`, one line in backticks) as the last child of the root: `logseq upsert block -g <graph> --target-uuid <uuid> --pos last-child --content '<line>'`.

7. **Verify.** `logseq-tree.py <graph> <uuid> 3` (`logseq show` can fail on trees with gfw macros). Check that every block from step 2 appears exactly once with the same db-id, that the headings are H2/H3 (`[:find ?b ?h :in $ [?b ...] :where [?b :logseq.property/heading ?h]]`), and that the Related refs resolved (`[:find (pull ?b [:db/id {:block/refs [:db/id]}]) :in $ [?b ...]]` on a few ref blocks). `scripts/logseq-enrich.py apply <plan.json> --dry-run` should now report 0 headings, 0 retitles and 0 refs to add.

8. **Report** the graph, the number of H2s and H3s, blocks moved and left ungrouped, link texts changed, gfw widgets added, links that got Related refs (and how many refs), and anything that failed or didn't verify.

## Notes

- Large inboxes (hundreds of links) are fine: `dump` and `related` take seconds, `apply` makes one CLI call per op (~0.5 s each).
- If the user changes how groups, headings or Related blocks should look, update this file (`~/Projects/installs/nix/dotfiles/agent-skills/logseq-enrich-blocks/SKILL.md`) and the script, and tell them to run `hms`. Link-text and gfw rules belong in `logseq-add-md-to-blocks` and its `logseq_links.py`, not here.
