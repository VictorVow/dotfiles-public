---
name: hn-favorites-digest
description: Work through the user's Hacker News favorites, oldest-posted first (only items posted more than 3 days ago): summarise each article, analyse every comment in its HN discussion for sentiment and notable insights (resources, perspectives, tips, quotes), write the digest into Logseq, then un-favorite the item on HN.
argument-hint: "<logseq block uuid | page name> [graph] [auto|manual]"
allowed_tools:
  - Bash
  - Read
  - Write
  - Agent
  - WebFetch
  - AskUserQuestion
  - Skill
user_invocable: true
---
Arguments: `$ARGUMENTS`: the Logseq target (a block `[[<uuid>]]`/uuid, or a page name), optionally a graph name, and optionally the mode, `auto` or `manual`. Ask for the target if it's missing. If no mode is given, ask with AskUserQuestion (options "Manual (Recommended)" / "Auto").

The helper is `~/Projects/installs/scripts/hn-favorites.py` (run it directly; it's a `uv run --script`). It prints JSON. Its `--help` explains every subcommand. Below, `hnf` means that script.

**Modes.** Items are always processed one at a time, never in parallel.

- **auto**: keep going through the queue, item after item, without waiting for the user, until `next` reports nothing eligible (or the user interrupts). Keep your per-item messages to one line so the context lasts.
- **manual**: after each item's blocks are in Logseq, stop and ask the user to review them (step 4e′). Un-favorite and move on only once they approve.

## Steps

1. **Load `logseq-add-md-to-blocks`** with the Skill tool, once, at the start. Every write to Logseq in this skill follows it, so the blocks are formatted the way the user wants. Use its steps 1–2 now to pick the graph (the named one, otherwise the `electron` one in `logseq server list`) and check the target. Its rules are kept up to date there; if anything below disagrees with it, that skill wins.

2. **Check the HN login:** `hnf status`. If `cookie` is not `valid`, stop and ask the user to run this in their own terminal (never ask for, or handle, the password or cookie yourself):
   ```
   ~/Projects/installs/scripts/hn-favorites.py login --cookie "<value of the user cookie for news.ycombinator.com, from the browser>"
   ```

3. **Refresh the queue:** `hnf scan` (about 1.5 minutes: HN is throttled to one request per 5s). It merges into the existing queue. Ordering is by posting date, oldest first. If `unfave_links` is 0 while logged in, stop: the favorites markup changed.

4. **Get the next item:** `hnf next` (one item, the oldest-posted eligible). Exit code 1 means nothing is eligible: report that and stop. Otherwise process it with a–f below, then come back to this step for the next item.

   a. If its `state` is `written`, it's already in Logseq (block `block`): in auto mode skip to (f); in manual mode skip to (e′), since the user hasn't approved it yet.

   b. **Fetch the discussion:** `hnf comments <id> --out-dir /tmp/hn-digest/<id>`. It writes **every** comment, threaded, to `comments-NN.txt` chunks (about 50k tokens each), plus `post.txt` for self-posts and comment favorites (story, parent comment, the favorited comment). Note the `chunks` and `comments` counts it prints. Don't read these files yourself: pass the paths to subagents, so your own context stays small.

   c. **Analyse each chunk** with a subagent (Claude Code: `Agent`, general-purpose; Devin: `run_subagent` with `subagent_general`), one chunk at a time. Prompt (fill in the placeholders):

      > Read `/tmp/hn-digest/<id>/comments-NN.txt` in full: chunk NN of N of the Hacker News discussion of "<title>" (<url>). Every comment starts with `[c<comment id>] <author> d<depth>:`; indentation shows replies. Write `/tmp/hn-digest/<id>/insights-NN.md` with:
      > - `## Sentiment`: how the thread received the article; the main camps and roughly what share of comments each holds; the main disagreements and how they played out.
      > - `## Resources`: every link, book, paper, tool, project or dataset someone recommends or cites, with its URL (as a Markdown link titled with what it is) and one line on why it was mentioned.
      > - `## Perspectives & experiences`: unique, expert or first-hand viewpoints, and stories from people who did the thing, not generic opinions.
      > - `## Tips`: practical, actionable advice.
      > - `## Quotes`: pithy sayings and memorable lines, verbatim.
      >
      > This is the main point of the exercise, so be exhaustive: go through every comment, and include every notable, useful insight however small the subthread. Only merge points that are genuinely repeated. Cite every item as `([author](https://news.ycombinator.com/item?id=<comment id>))`. Follow the link and title rules in step 3 of `~/.claude/skills/logseq-add-md-to-blocks/SKILL.md` (read it first): Markdown links titled with the target's own title, no bare URLs, "issue 123" / "PR 123" never "#123", no `[[`, `#` escaped as `\#` in titles. Reply with just "done" and the number of comments covered.

   d. **Write the digest** with one more subagent:

      > Write `/tmp/hn-digest/<id>/summary.md`, a digest of the Hacker News item "<title>" (<url>, <points> points, <comments> comments, posted <date>; HN: https://news.ycombinator.com/item?id=<id>).
      > 1. The article: fetch <url> (WebFetch; if that fails, `curl -sL` and pull out the readable text). For a self-post or comment favorite, read `/tmp/hn-digest/<id>/post.txt` instead. If the link is dead or paywalled, say so in one line and carry on.
      > 2. The discussion: read every `/tmp/hn-digest/<id>/insights-*.md`, merge them (combine the sentiment sections into one, de-duplicate the lists), and drop nothing else.
      >
      > Exact format: no H1, no hard wrapping, empty sections omitted, the same citation style as the insights files, and the link and title rules in step 3 of `~/.claude/skills/logseq-add-md-to-blocks/SKILL.md` (read it first). In the link text of the heading, escape `#` as `\#`, drop any `]`, and don't start it with `[[`:
      > ```
      > ## [<title>](<url>)
      > [HN discussion](https://news.ycombinator.com/item?id=<id>) · <points> points · <comments> comments · posted <YYYY-MM-DD>
      > ### Article
      > <summary: what it says, key claims and evidence; a few bullets or short paragraphs>
      > ### Discussion
      > #### Sentiment
      > #### Resources
      > #### Perspectives & experiences
      > #### Tips
      > #### Quotes
      > ```
      > For a comment favorite, the heading is `## <author> on: [<story title>](<story url>)` and `### Article` becomes `### Comment`: the favorited comment (quoted) and its context. Reply with just "done".

      If there's only one chunk, steps c and d can be a single subagent: give it both prompts.

   e. **Write to Logseq** by following `logseq-add-md-to-blocks` steps 4–7 (convert, dry run, write, verify), with `/tmp/hn-digest/<id>/summary.md` as the input file, `/tmp/hn-digest/<id>/blocks.md` as the output, and the target from step 1 with `--pos last-child`. In particular:
      - Before converting, skim `summary.md` against that skill's step 3 formatting and link rules and fix anything the subagent got wrong.
      - Convert with `--gfw` when the digest has blocks that start with GitHub links (e.g. in Resources), as that skill says.
      - Do the dry run for every item. If `would-create-pages` isn't empty, find the cause in `summary.md` (`grep -n '\[\[\|#[A-Za-z]'`), fix it, and convert again; only ask the user if you can't fix it.
      - The real write prints the new block ids. Immediately record the first one (the `## …` heading block): `hnf mark <id> written --block <id>`. This makes a re-run skip the write even if a later step fails. Then do that skill's verify step.

   e′. **Manual mode only: review gate.** Tell the user, in a few lines, where the blocks are (graph, target, the heading's block id), the item's title and its comment/chunk counts. Then ask with AskUserQuestion whether the summary is acceptable and it's OK to continue, with options:
      - "Looks good, continue": go to (f), then on to the next item, which ends at this same gate.
      - "Looks good, stop here": do (f), then report (step 5) and stop.
      - "Needs changes" (the user describes them via Other/notes): apply the changes to `summary.md` (re-run the step-d subagent with the feedback if it's about content, edit the file yourself if it's about wording or format), delete the written blocks with `logseq remove block -g <graph> --id <heading block id>` (removes its children too; check with `logseq show`), write again as in (e), `hnf mark <id> written --block <new id>`, and ask again. Don't un-favorite until the user approves.

      If the run ends at this gate without an answer, the item stays `written` and the next run starts with it (see a).

   f. **Un-favorite:** `hnf remove <id>`. It checks the item page afterwards and marks the item `done`.

   On any failure in b–f: `hnf mark <id> failed --error "<short reason>"` (but if the Logseq write already happened, leave it `written`), tell the user, and continue with the next item. Failed items are skipped by `next` until `hnf mark <id> pending` (or `next --include-failed`).

5. **Report** (at the end of an auto run, or when the user stops a manual one): each item processed (title → Logseq target, comment count, chunk count), anything left `written` (in Logseq but still favorited) or `failed`, and the `eligible` count from `hnf status`.

## Notes

- HN rate-limits hard. The script waits 5s between HN requests (shared across runs) and backs off on the "Sorry" page. Don't call HN in any other way (curl, WebFetch) while this skill runs.
- The 3-day minimum (`--min-age-days`) counts from the item's posting date, so the discussion has settled before it's analysed.
- State: `~/.local/state/hn-favorites/queue.json`. Cookie: `~/.config/hn-favorites/cookie`. Scratch: `/tmp/hn-digest/<id>/`.
