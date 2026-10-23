---
name: search-agent-history
description: Search past coding-agent sessions (Claude Code, OpenCode, Devin CLI, plus Codex/Copilot/Gemini) for how something was done, decided, or debugged before, using the cass CLI. Use when the user asks "did we/I/you ever…", "how did we fix X last time", "find the session where…", or wants to resume or cite an earlier conversation.
compatibility: "Requires the cass CLI"

---

Searches the [cass](https://github.com/Dicklesworthstone/coding_agent_session_search) index of agent transcripts. Each host has its own index covering only sessions that ran there — there is no shared/federated index:

- **boss** (desktop) — `cass` on PATH via brew; index at `~/.local/share/coding-agent-search`, with MiniLM semantic vectors
- **lord-ubuntu** — `~/.local/bin/cass` (upstream tarball, same version); index at the same path, covering sessions spawned on the server (Orca `orca-ide serve`, direct SSH runs)

Use the bundled `scripts/cass-remote.sh` to pick a host. It handles the SSH dispatch, BatchMode, ConnectTimeout and `timeout` wrapper:

```bash
scripts/cass-remote.sh boss        search "…" --json
scripts/cass-remote.sh lord-ubuntu search "…" --json
scripts/cass-remote.sh local       sessions --json   # 'local' = run on PATH
```

On lord-ubuntu itself the skill runs locally — `boss` would be the SSH leg instead. Aliases `local`/`desktop`/`server` are accepted on either side.

## Rules

- **Never run bare `cass`.** It opens a TUI and blocks the shell. Every call needs `--robot`/`--json` (or a subcommand that prints JSON).
- **Learn the CLI from cass itself, not from memory or this file.** Flags change between versions. Once per session, before the first search, run:
  - `cass robot-docs guide` (workflow and contracts, ~5 KB)
  - `cass robot-docs examples` (copy-paste invocations)
  - and, when you need them: `cass robot-docs commands`, `cass robot-docs schemas`, `cass robot-docs exit-codes`, `cass capabilities --json` (connector names, features), `cass introspect --json` (full arg/response schema, large: pipe through `jq` for the part you need).
  - Command fails or a flag is rejected → read the JSON error (`err.kind`, suggested fix) and `cass <cmd> --help`. Don't guess.
- Wrap every call in a caller-side deadline. `cass-remote.sh` already does this (30s local, 45s remote). Check `budget.timed_out` even on exit 0: empty timed-out hits don't prove nothing exists.
- Read-only by default. Don't run `doctor --fix`, `forget`, `models …`, `schedule …` or full rebuilds without asking the user.

## Workflow

1. **Pick the host(s).** Decide where the session ran:
   - Question is about a desktop workspace, a desktop repo (`~/Projects/installs`, `~/Projects/Git/…`), or anything involving a GUI/browser/clipboard → `boss` only.
   - Session was spawned by `orca-ide serve` on lord-ubuntu, was an SSH session, or is about `~/installs` / `~/Projects/Self-Hosted` *on the server* → `lord-ubuntu` only.
   - "Did we ever…" with no hint, anything cross-host, or first query came back empty and the user expected a hit → run **both in parallel** and merge the JSON hit arrays before ranking.
   - Workspace paths differ per host — translate `~/Projects/installs` ↔ `~/installs` and `~/Projects/Git/1MY_REPOS` ↔ `~/Projects` when filtering a query that names a path on the other host.
2. **Refresh.** Run an incremental index so today's sessions are searchable: `cass-remote.sh <host> index --json --no-progress-events` (one per host you're querying). A no-op when nothing changed. Skip it if the user only wants older history.
3. **Scope.** Work out the agent, the project and the time range from the request.
   - Agent connector names: `claude_code`, `opencode`, `devin` (confirm with `cass-remote.sh <host> capabilities --json | jq .connectors`). Omit `--agent` to search all.
   - Workspace: default to the current repo (`--workspace "$(pwd)"`) when the question is about this project. Drop it when the user says "anywhere", or asks about another project. On the remote host, translate the path first (step 1).
   - Time: `--days N` / `--since` / `--today` / `--week`.
4. **Search.** Start small and cited (`--limit` ~5–10, `--fields` minimal or summary, `--max-tokens`, `--robot-meta`), following the "Quick history" pattern in `robot-docs guide`.
   - Mode: keyword/error-string/identifier → `--mode lexical`. Conceptual ("where did we discuss caching strategy") → default hybrid or `--mode semantic`. Check `_meta` for the realized mode and any `fallback_reason`.
   - Exclude the current session: hits from `cass-remote.sh <host> sessions --current --json` are this conversation echoing the query back.
   - Nothing found → broaden one dimension at a time (drop workspace, widen days, try synonyms or wildcards, switch mode, try the other host), and say what you tried.
5. **Read.** Expand only the promising hits with `cass-remote.sh <host> view` / `expand` using the hit's `source_path` + message index/line (exact flags are in `robot-docs guide`). Keep the context small (`-C 3`) and check the size before pulling large records into context. Remote `source_path`s are valid on that host — `cass view` on the remote resolves them; don't try to open them locally.
6. **Answer.** Summarize what was found. Cite each claim with **host**, agent, date, workspace and `source_path` (+ line/message index). Quote the decisive lines. Distinguish what was *decided/done* from what was only *discussed*.
7. **Resume (if asked).** For Claude Code and OpenCode, `cass-remote.sh <host> resume <source_path> --shell` prints the native resume command — note it has to run *on that host* (SSH in first if it's the remote one). cass doesn't support Devin; use `devin --resume <session-id>` on the matching host, where the id is the last segment of the hit's `source_path` (`…/devin/cli/sessions.db/steady-splash` → `steady-splash`). Give the command to the user rather than running it (it starts an interactive agent, and must run from the session's workspace).

For a handoff to another agent, or a long multi-session summary, prefer `cass-remote.sh <host> pack "<question>" --robot` with token budgets over many separate searches (see `robot-docs guide`, "Pack"). It's per-host, so pack on the host where the relevant sessions live (or both and concatenate).

## Readiness problems

Search errors with `maintenance-required`, semantic is unavailable, or results look stale → run `cass-remote.sh <host> health --json` (read-only) and report `recommended_action`/`recommended_commands` to the user, prefixed with the host. `cass-remote.sh <host> triage --json` gives a fuller diagnosis. Only run the suggested mutating commands with the user's OK.

SSH failure to lord-ubuntu (ConnectTimeout, host down, `BatchMode` auth fail) → say so and fall back to local-only results; don't keep retrying.
