---
name: system-update-changelog
description: Add a dated section to ~/Projects/installs/CHANGELOG.md summarising the workflow-affecting changes made to the installs repo and the Self-Hosted repos since the last entry.
---

Adds one section to `~/Projects/installs/CHANGELOG.md` covering the changes in two places:

- `~/Projects/installs/` (one git repo)
- `~/Projects/Git/1MY_REPOS/Self-Hosted/`. This is **not** a git repo itself. Each service subdirectory (`FreeLLMAPI/`, `Orca-server/`, `1-COMMON/`, …) is its own repo. Directories without a `.git` are skipped.

## 1. Work out the time range

- Read `CHANGELOG.md`. Sections are newest first, each headed `## YYYY/MM/DD Day`, optionally suffixed with ` [WIP]` while that day is still in progress.
- **Start** = the day after the newest section's date. If the file is empty or has no sections, start = today.
- If the newest section is already **today**, update that section: merge the new items into it and don't repeat what's already there. Keep the ` [WIP]` suffix on its heading.
- If the newest section is for an earlier day, that day is over: remove the ` [WIP]` suffix from its heading when you add the new section.
- **End** = now. Include uncommitted and staged changes (`git status --short`, `git diff`, `git diff --cached`) as well as commits. Uncommitted work is usually what the user just did with an agent.

## 2. Gather changes

installs repo:

```bash
git -C ~/Projects/installs log --since=<START>T00:00 --format='%h %ad %s%n%b' --date=short --stat
git -C ~/Projects/installs status --short && git -C ~/Projects/installs diff --stat
```

Self-Hosted repos:

```bash
cd ~/Projects/Git/1MY_REPOS/Self-Hosted
for d in */; do [ -d "$d/.git" ] || continue
  out=$(git -C "$d" log --since=<START>T00:00 --format='  %h %s'); st=$(git -C "$d" status --short)
  [ -n "$out$st" ] && printf '## %s\n%s\n%s\n' "$d" "$out" "$st"; done
```

If a subject line doesn't tell you what changed for the user, read the commit body or the diff (`git show <hash>`). For new services, skills or tools, also read the relevant README or `SKILL.md`.

## 3. Filter: only workflow changes

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

## 4. Write the section

- Heading: `## YYYY/MM/DD Day [WIP]`, using today's date (`date '+%Y/%m/%d %A'`), e.g. `## 2026/10/19 Monday [WIP]`. The ` [WIP]` suffix marks that the day isn't over yet and the section may still grow; it comes off once a newer day's section is added.
- Insert it at the **top** of the file (below any `# Changelog` title or `> ` quote block, which you never edit), with one blank line between sections.
- Body: a flat bullet list, most notable first. One line per item: **bold name** + a short description of what it does / how to use it. Group closely related items (e.g. a service plus its backup and its Firefox allowlist entry) into one bullet. No hard wrapping.
- Prefix Self-Hosted items with the service name, e.g. `**FreeLLMAPI** (Self-Hosted): …`.
- No commit hashes, no file paths unless the path is what the user types or opens.

Show the user the new section once it's written. Don't commit unless they ask.
