---
name: system-update-cvlog
description: Update ~/Projects/installs/CVLOG.md, the user's running list of skills and experience (grouped by skill/category, each item dated and backlinked to a git commit, Logseq block or agent session), from the work done in the installs repo, the Self-Hosted repos, Logseq and agent sessions since the last update. It's the reference for writing a CV/resume later.
---

Updates `~/Projects/installs/CVLOG.md`, a list of the skills and experience the user has built up. It isn't a CV itself: it's the raw material the user will pick from when writing one later, so each item must say what was done and point back to the evidence.

Sources:

- `~/Projects/installs/` (one git repo)
- `~/Projects/Git/1MY_REPOS/` (the user's own projects). This is **not** a git repo itself. Under `Self-Hosted/` each service subdirectory (`FreeLLMAPI/`, `Orca-server/`, `1-COMMON/`, …) is its own repo, but some are grouped one level deeper (`Miruyomi/Miruyomi-Server`, `Headscale-server/Headscale-deploy`, `Proxy-Frontends/Reddit`, `MediaManager/…`); `System-Tray-App/` holds more repos the same way. Some of these nested dirs are upstream clones or forks: count only commits by the user (author `Victor`/`VictorVow`/`USER3`/`USER2`).
- The user's GitHub pull requests to other projects (`gh search prs --author VictorVow`)
- The Logseq graph `logseq-apex` (notes, research, projects the user wrote up)
- Past agent sessions in the cass index (debugging and diagnosis work that never produced a commit)

## File format

```markdown
**Last updated:** 2026/10/20 Tuesday

## Nix / Home Manager

- **Secrets management**: encrypted rclone and AI-provider credentials with **sops-nix** and age, decrypted at activation `2026/05/02, git commit: installs 8be01d4`
- **Workstation migration**: moved all user-space packages from apt, Homebrew, pipx and npm to a declarative Home Manager flake `2026/03/14, git commit: installs 3f9a2c1`

## Self-hosting & container infrastructure

### Platform

- **Shared Caddy edge**: … `2026/05/23, git commit: 1-COMMON 1ae2ae9`

### Services

- **FreeLLMAPI**: … `2026/10/19, git commit: FreeLLMAPI 5abe4a7`

## Networking

- Diagnosed packet loss across a Tailscale/Headscale mesh with per-segment latency and iperf3 throughput tests `2026/09/30, agent session: 3c1e…`
```

- First line: `**Last updated:** YYYY/MM/DD Day` (`date '+%Y/%m/%d %A'`). There is exactly one; replace it on every run.
- Then one `## ` section per skill or category, named after the top-level skill as it would appear on a CV (e.g. `Nix / Home Manager`, `Linux system administration`, `Self-hosting`, `Networking`, `Ansible`, `Shell scripting`, `Python`, `AI agents & tooling`, `Browser / Firefox internals`, `Security & secrets management`, `Technical research & writing`). Reuse an existing heading whenever one fits; only add a new one when nothing does. Keep sections in a sensible order (most substantial first), not by date.
- Subheadings: when a section has enough bullets to fall into natural groups (roughly 6+), split it with `### ` subheadings (e.g. `Platform` / `Services`, `Merged` / `Proposed & forks`, `Configuration & automation` / `Diagnosis`). Reuse existing subheadings; don't add one for a single bullet.
- Bold: each bullet opens with a **bold label** naming the project, tool or problem, then a colon (`- **Headscale**: ran a …`). Within the text, bold the key technologies a recruiter would scan for (languages, frameworks, major tools), sparingly: two or three per bullet at most.
- Bullets: one line each, no hard wrapping. After the label, use a past-tense verb and describe **what the user did and with which tools/technologies**, phrased so it could be lifted into a CV (concrete, outcome-focused, no internal jargon like file paths or alias names unless they matter). Group a run of commits that make up one piece of work into one bullet.
- End each bullet with the date and backlink in inline code: `` `YYYY/MM/DD, <backlink>` ``. The date is when the work was done (the commit date, the block's creation date, the session date; for a bullet spanning several days use the last day). Backlinks:
  - `git commit: <repo> <7-char hash>`, where `<repo>` is `installs` or the Self-Hosted directory name (e.g. `git commit: Headscale 1a2b3c4`). For grouped commits, cite the most representative one, or up to three separated by commas.
  - `logseq block ID: <uuid>`
  - `GitHub PR: <owner>/<repo>#<number>` (several from one repo: `GitHub PR: logseq/logseq#12656, #12696`)
  - `agent session: <session id>` (the id from cass, plus the agent if not Claude Code, e.g. `agent session: devin steady-splash`)
- Within a section or subsection, newest bullets first.

## 1. Work out the time range

- Read `CVLOG.md` and take the date from the `Last updated:` line. **Start** = that date (inclusive: work later that same day may not be in yet). Everything already listed is skipped by matching its backlink, so overlapping a day is safe.
- If the file is empty or has no `Last updated:` line, this is the first run: cover the full history of the git repos, and ask the user how far back to go for Logseq and agent sessions (they can be large).
- Only committed work counts. Uncommitted changes have no hash yet; they'll be picked up once committed.

## 2. Gather

installs repo:

```bash
git -C ~/Projects/installs log --since=<START>T00:00 --format='%h %ad %s%n%b' --date=short --stat
```

Own repos (top-level and one level nested):

```bash
cd ~/Projects/Git/1MY_REPOS
for d in Self-Hosted/*/ Self-Hosted/*/*/ System-Tray-App/*/; do [ -e "$d/.git" ] || continue
  out=$(git -C "$d" log --since=<START>T00:00 --author='Victor\|VictorVow\|USER3\|USER2\|boss' --format='  %h %ad %s' --date=short)
  [ -n "$out" ] && printf '## %s\n%s\n' "$d" "$out"; done
```

Pull requests:

```bash
gh search prs --author VictorVow --created '>=<START>' --limit 100 --json repository,title,state,createdAt,number \
  --jq '.[]|"\(.createdAt[0:10]) \(.state) \(.repository.nameWithOwner)#\(.number) \(.title)"'
```

Merged PRs are the strongest evidence; open/closed ones still show the work. Where a fork's commits were upstreamed, cite the PRs rather than the fork commits.

If a subject line doesn't make the work clear, read the body or diff (`git show <hash>`), and the relevant README / `SKILL.md` for new services, skills and tools.

Logseq (see the `logseq-cli` skill; if no server is running, `logseq server start -g logseq-apex`). Blocks created since the start date, with their page:

```bash
since=$(date -d <START> +%s)000
logseq query -g logseq-apex -o json --inputs "[$since]" --query '[:find ?u ?pt ?t ?c :in $ ?since :where [?b :block/created-at ?c] [(>= ?c ?since)] [?b :block/uuid ?u] [?b :block/title ?t] [?b :block/page ?p] [?p :block/title ?pt]]'
```

The graph is large (tens of thousands of new blocks a month, mostly hobby pages and agent-imported digests), so narrow it: keep only tech/work pages (e.g. `Programming`, `Technology`, `Software`, `PC`, `Current Job`, `Logseq`, language pages), only the top two outline levels (`[?b :block/parent ?p]` or one level below), and drop days with bulk imports (check the per-day count first). Group the result by page and skim it for things the user did: projects, research they carried out, things they set up, built, fixed or learned. Use `logseq show -g logseq-apex --uuid <uuid>` to read a block's subtree. Ignore agent-written bulk content (Hacker News digests, imported research outlines, anything tagged `AI-GENERATED`) except as evidence that the user directed a piece of research; ignore journals' routine entries, quotes, highlights and reading lists.

Agent sessions: follow the `search-agent-history` skill for the cass CLI (refresh the index, then `cass sessions --since <START> --limit 5000 --json` and tabulate date/agent/workspace/id/title). Devin and OpenCode sessions often have no date; date them from the matching commits or skip the date-dependent claim. Look for sessions where a real problem was diagnosed or something was built that didn't end in a commit to the repos above (e.g. troubleshooting a crash, a GPU/driver issue, a VM, a network problem). The memory files in `~/.claude/projects/*/memory/` are a quick index of such investigations; find the matching session for the backlink. Skip sessions whose work is already covered by a commit.

## 3. Filter: only CV-worthy experience

Keep something if it shows a **skill, a technology used in anger, or a problem solved**: something the user could talk about in an interview. Examples:

- Building or migrating infrastructure (a new self-hosted service, a declarative config layer, a backup scheme, CI/lint tooling)
- Writing tools and scripts (Claude skills, diagnostic toolkits, automation)
- Non-trivial debugging and root-cause analysis (performance, crashes, networking, drivers, sandboxing)
- Security work (secrets management, supply-chain pinning, hardening, DNS/mail authentication)
- Research and evaluations that led to a decision

Leave out:

- Trivial changes: version bumps, lock updates, typo and lint fixes, renames, small config tweaks
- Repo housekeeping: history rewrites, `.gitignore`, moving files, README resyncs
- Anything already in `CVLOG.md` (same backlink, or the same piece of work under another backlink: extend that bullet's backlinks or wording instead of adding a duplicate)

A refactor or doc change can still count if it's substantial in its own right (e.g. restructuring a monolithic script into modules, writing a research comparison). Judge the work, not the commit type.

## 4. Write

- Add the new bullets to the right sections (creating sections as needed), update the `Last updated:` line, and keep the file free of hard wrapping.
- Never edit `> ` quote blocks the user may have added.
- If an existing bullet's skill heading now fits better under a newly created section, leave it unless the user asks: they may have placed it deliberately.

Show the user the bullets you added (grouped by section) once written. Don't commit unless they ask.
