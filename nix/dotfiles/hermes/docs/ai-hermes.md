# Hermes Agent (this machine)

Hermes runs two profile homes on boss-laptop:

| Profile | `$HERMES_HOME` | Used by |
|---------|----------------|---------|
| Default | `/home/boss/.hermes` | The `hermes`/`@hermes` agent (CLI sessions, teammate roster's default) |
| `installs` | `/home/boss/.hermes/profiles/installs` | The Installs agent (`hermes desktop` profile switch — the agent that works on this repo) |

`~/.hermes` is a plain directory on disk (NOT relocated, NOT a symlink —
hermes-desktop requires `realpath($HERMES_HOME) == $HERMES_HOME` and refuses a
symlinked home with "Noncanonical gateway profile", hanging on CONNECTING).

What this repo tracks is only the **agent-authored** content:

| Live path | Backed by |
|-----------|-----------|
| `~/.hermes/memories/` | symlink → [`../memories/`](../memories/) — default profile memory |
| `~/.hermes/profiles/installs/memories/` | symlink → [`../profiles/installs/memories/`](../profiles/installs/memories/) |
| `~/.hermes` agent-created skills | `skills.create_dir` → [`../skills/`](../skills/) — scanned in place, no symlinks |
| `~/.hermes/profiles/installs` agent-created skills | `skills.create_dir` → [`../profiles/installs/skills/`](../profiles/installs/skills/) — scanned in place |

Everything else under `~/.hermes` (state.db, sessions, auth.json, `.env`,
config.yaml, bundled skills catalog, logs, cache, kanban, …) is runtime state
or secrets and stays local — nothing in `agent-skills.nix`/`home.nix` writes
into it. New agent-created skills land directly in the matching repo skills
dir because both profiles' `config.yaml` set `skills.create_dir` there
(Hermes scans `create_dir` alongside `$HERMES_HOME/skills/`); no symlink or
home-manager change is needed for each new skill. Skills created *before*
this was set, or hub-installed ones still under `$HERMES_HOME/skills/`, can
be moved into the matching repo dir manually.

Each profile keeps its own sessions, memory, skills, config, cron and logs; nothing is shared
between them unless configured below.

## Memory — on-disk locations

Hermes' built-in memory is plain Markdown, one file per store, injected into every
session's context (subject to a character budget):

| File | Purpose | Exists |
|------|---------|--------|
| `$HERMES_HOME/memories/MEMORY.md` | Agent's own notes: environment facts, conventions, lessons | Both profiles (`installs` has one entry; default's is created on first write) |
| `$HERMES_HOME/memories/USER.md` | Who the user is: name, role, preferences, style | Created on first `user`-target memory write |
| `$HERMES_HOME/memories/*.lock` | Write locks (empty files) | alongside each `.md` |

- The agent writes these via its `memory` tool (`add`/`patch`/`remove` against targets
  `memory` = MEMORY.md, `user` = USER.md) — only it should write there; hand-edits risk
  breaking the agent's char-budget bookkeeping.
- `hermes memory reset` erases both files; `hermes memory setup` configures an external
  provider instead (retaindb/byterover built in, Honcho/mem0/supermemory/… via plugins —
  none active here; built-in MEMORY.md/USER.md stays active regardless).
- Session history (transcripts) is NOT in `memories/` — it's `$HERMES_HOME/state.db`
  (SQLite+FTS5) plus `$HERMES_HOME/sessions/`, indexed machine-wide by the `cass` CLI
  (Brewfile) via the `search-agent-history` skill.

So for the Installs agent specifically: **memory lives at
`/home/boss/.hermes/profiles/installs/memories/`** (a symlink into
`nix/dotfiles/hermes/profiles/installs/memories/` in this repo) and the
default agent's at `/home/boss/.hermes/memories/` (symlinked into
`nix/dotfiles/hermes/memories/`).

## Skills — on-disk locations

Each profile loads skills from, in precedence order (highest first):

1. **Project-local** trusted repo dirs (`.hermes/skills`, `.agents/skills` — only after
   `hermes skills trust <repo>`; not used in this repo)
2. **`$HERMES_HOME/skills/`** — the profile's own dir. On this machine each holds
   the bundled catalog (~90 skills) seeded from the Hermes repo, as category dirs
   (`autonomous-ai-agents/`, `productivity/`, `software-development/`, …) each with
   one SKILL.md per skill.
3. **`skills.create_dir`** — redirect for new skill creation. **Set on both
   profiles** (2026-11-02) to the repo dir: `~/Projects/installs/nix/dotfiles/hermes/skills`
   (default) and `.../profiles/installs/skills` (installs profile). It is scanned
   alongside the local dir, so agent-created skills live in git directly — e.g.
   `config-repo-review/`, `nix-home-manager-ops/`,
   `hermes-desktop-outside-in-debugging/` under the installs profile. The agent
   maintains them with `skill_manage`; the curator tidies them.
4. **`skills.external_dirs`** in `$HERMES_HOME/config.yaml — extra scan roots. Set on
   **both** profiles (2026-11-02) to `~/.claude/skills`, which exposes the repo's
   `agent-skills` (26 own + third-party symlinked skills) to Hermes — including as
   `/name` slash commands. Since `~/.claude/skills/<name>` symlinks into
   `nix/dotfiles/agent-skills/` here, agent `skill_manage` edits to those skills land
   in this repo (see the header comment of `nix/modules/agent-skills.nix` for the full
   per-agent scan-dir matrix).

CLI: `hermes skills list|install|update|reset|audit|…` (hub skills install into
`$HERMES_HOME/skills/`); in-chat every skill is a `/skill-name` slash command.
Skills follow the agentskills.io SKILL.md format — same as this repo's
`agent-skills`, which is why the symlink exposure works.

## See also

- `nix/modules/agent-skills.nix` header — which agent reads which skill dirs
- [docs/system/architecture.md](../../../docs/system/architecture.md) — how the Nix/Ansible layers fit
- Hermes docs: <https://hermes-agent.nousresearch.com/docs/user-guide/features/skills>
