---
name: system-update-changelog
description: Add a dated section to ~/Projects/installs/CHANGELOG.md summarising the workflow-affecting changes made to the installs repo and the Self-Hosted repos since the last entry. Entries are written in arrears — today's section is normally only added by tomorrow's run.
compatibility: "Requires git and access to the Self-Hosted repos"

---

Adds dated sections to the installs repo's `CHANGELOG.md` — one per covered day — covering the changes in two places:

- The installs repo itself (one git repo)
- The Self-Hosted services directory. This is **not** a git repo itself. Each service subdirectory (`FreeLLMAPI/`, `Orca-server/`, `1-COMMON/`, …) is its own repo. Directories without a `.git` are skipped.

## 0. Resolve paths for this host

The repo lives in different places per host — pick whichever exists:

- installs repo: `~/Projects/installs` (desktop `boss`) or `~/installs` (lord-ubuntu)
- Self-Hosted: `~/Projects/Git/1MY_REPOS/Self-Hosted` (desktop) or `~/Projects/Self-Hosted` (lord-ubuntu)

`CHANGELOG.md` sits at the root of whichever installs path resolved. Below, `$INSTALLS` and `$SELF_HOSTED` mean those resolved dirs.

## 1. Commit the user's own edits first

The user edits `CHANGELOG.md` by hand between runs. Their edits are mostly deletions and rewording, and only rarely additions. Before changing anything, check `git -C "$INSTALLS" diff -- CHANGELOG.md` (and `--cached`). If it shows changes, they are the user's: commit only that file on its own first, e.g. `docs(changelog): user updates`, with a body saying these are the user's own edits (deletions/rewording). Don't include other files in the commit. Then treat the committed text as final: don't re-add items they deleted or undo their wording.

## 2. Work out the time range

- Read `CHANGELOG.md`. Sections are newest first, each headed `## YYYY/MM/DD Day`, optionally suffixed with ` [WIP]` while that day is still in progress.
- **Start** = the day after the newest section's date (or that day's 00:00 if the newest section is for an earlier day and still has ` [WIP]` — see below). If the file is empty or has no sections, start = today.
- If the newest section is already **today**, it was created ahead of time — update it: merge in the new items from today so far, don't repeat what's already there, and make sure it carries the ` [WIP]` suffix (add it if missing). Don't add any other sections: today is still in progress, so don't close it out and don't backfill earlier days — they already have sections. Stop here.
- If the newest section is for an earlier day and still has ` [WIP]`, it was written before that day ended, so it is probably missing that day's later work. Finish it as part of the run: include that day in the range you gather, merge in what's missing under its existing heading, and drop "(uncommitted)" notes on items that have since been committed. Once that day is fully gathered its ` [WIP]` comes off, because the day is over.
- **End** = end of yesterday. Runs never document the current day: each day's changes are only processed and written up once that day is fully over. Anything changed today (including uncommitted/staged work) is left for a later run — never fold it into an earlier day's section. Work that was changed on a past day but is still uncommitted does belong to that day's section; use file mtimes, reflog dates, or the user's account of when the work happened to attribute it.

## 3. Gather changes

installs repo:

```bash
git -C "$INSTALLS" log --since=<START>T00:00 --until=<END>T23:59 --format='%h %ad %s%n%b' --date=short --stat
git -C "$INSTALLS" status --short && git -C "$INSTALLS" diff --stat
```

Self-Hosted repos:

```bash
cd "$SELF_HOSTED"
for d in */; do [ -d "$d/.git" ] || continue
  out=$(git -C "$d" log --since=<START>T00:00 --until=<END>T23:59 --format='  %h %ad %s' --date=short); st=$(git -C "$d" status --short)
  [ -n "$out$st" ] && printf '## %s\n%s\n%s\n' "$d" "$out" "$st"; done
```

Then split the gathered commits by their commit date and group them per day. Days with no workflow-relevant changes get no section at all.

If a subject line doesn't tell you what changed for the user, read the commit body or the diff (`git show <hash>`). For new services, skills or tools, also read the relevant README or `SKILL.md`.

## 4. Filter: only workflow changes

Keep a change only if it affects **how the user works day to day**: something new they can use or invoke, or something that now behaves differently. Examples:

- New or changed Claude skills (always list new ones, by `/name`), agents, hooks, MCP servers
- New or removed CLI tools, apps, aliases, keybindings, shell behaviour
- New, removed or deprecated self-hosted services, and new URLs or endpoints
- Changed startup/tmux layout, update flow, launcher entries
- Agent CLI version/config switches (e.g. OpenCode v1 → v2), new secrets that unlock a feature

Leave out:

- Refactors and file moves/splits, lint/warning fixes with no visible effect, flake/lock bumps
- Git and repo housekeeping: history rewrites, force-pushes, purged or untracked files, `.gitignore`, remotes, branch cleanup
- Doc-only edits (including research notes and README resyncs), generated state-inventory syncs
- Internal backup plumbing, unless it changes what the user has to do

The test is about **using the system**, not maintaining the repos. If unsure, ask: "does this change what the user can run, open or invoke, or how something they use behaves?" If the answer is only "they might need to know it for repo maintenance", leave it out.

## 5. Write the sections

- Write one section per covered day that has workflow-relevant changes, newest first. Heading: `## YYYY/MM/DD Day`, using the covered day's own date, e.g. `## 2026/10/19 Monday`. Never create a section headed with today's date — if one already exists it keeps its ` [WIP]`; every section you write is for a finished day and carries no suffix.
- Each day's section lists only changes committed (or, for still-uncommitted work, made) on that day. Don't move a change to a different day's section and don't lump several days into one.
- Insert the new sections at the **top** of the file (below any `# Changelog` title or `> ` quote block, which you never edit), with one blank line between sections.
- Body: a flat bullet list, most notable first. One line per item: **bold name** + a short description of what it does / how to use it. Group closely related items (e.g. a service plus its backup and its Firefox allowlist entry) into one bullet. No hard wrapping.
- Prefix Self-Hosted items with the service name, e.g. `**FreeLLMAPI** (Self-Hosted): …`.
- No commit hashes, no file paths unless the path is what the user types or opens.

Show the user the new sections once they're written, then end the run by loading the `git-commit` skill and committing the session's changes.
