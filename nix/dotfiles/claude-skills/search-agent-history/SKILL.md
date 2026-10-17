---
name: search-agent-history
description: Search past coding-agent sessions (Claude Code, OpenCode, Devin CLI, plus Codex/Copilot/Gemini) for how something was done, decided, or debugged before, using the cass CLI. Use when the user asks "did we/I/you ever…", "how did we fix X last time", "find the session where…", or wants to resume or cite an earlier conversation.
---

Searches the local [cass](https://github.com/Dicklesworthstone/coding_agent_session_search) index of agent transcripts. cass is installed via the repo `Brewfile` (data stores and formats are listed in its comment there). Its index lives in `~/.local/share/coding-agent-search`, with MiniLM semantic vectors.

## Rules

- **Never run bare `cass`.** It opens a TUI and blocks the shell. Every call needs `--robot`/`--json` (or a subcommand that prints JSON).
- **Learn the CLI from cass itself, not from memory or this file.** Flags change between versions. Once per session, before the first search, run:
  - `cass robot-docs guide` (workflow and contracts, ~5 KB)
  - `cass robot-docs examples` (copy-paste invocations)
  - and, when you need them: `cass robot-docs commands`, `cass robot-docs schemas`, `cass robot-docs exit-codes`, `cass capabilities --json` (connector names, features), `cass introspect --json` (full arg/response schema, large: pipe through `jq` for the part you need).
  - Command fails or a flag is rejected → read the JSON error (`err.kind`, suggested fix) and `cass <cmd> --help`. Don't guess.
- Wrap every call in a caller-side deadline (`timeout 30s cass …`), and check `budget.timed_out` even on exit 0: empty timed-out hits don't prove nothing exists.
- Read-only by default. Don't run `doctor --fix`, `forget`, `models …`, `schedule …` or full rebuilds without asking the user.

## Workflow

1. **Refresh.** Run an incremental index so today's sessions are searchable: `timeout 120s cass index --json --no-progress-events`. A no-op when nothing changed. Skip it if the user only wants older history.
2. **Scope.** Work out the agent, the project and the time range from the request.
   - Agent connector names: `claude_code`, `opencode`, `devin` (confirm with `cass capabilities --json | jq .connectors`). Omit `--agent` to search all.
   - Workspace: default to the current repo (`--workspace "$(pwd)"`) when the question is about this project. Drop it when the user says "anywhere", or asks about another project.
   - Time: `--days N` / `--since` / `--today` / `--week`.
3. **Search.** Start small and cited (`--limit` ~5–10, `--fields` minimal or summary, `--max-tokens`, `--robot-meta`), following the "Quick history" pattern in `robot-docs guide`.
   - Mode: keyword/error-string/identifier → `--mode lexical`. Conceptual ("where did we discuss caching strategy") → default hybrid or `--mode semantic`. Check `_meta` for the realized mode and any `fallback_reason`.
   - Exclude the current session: hits from `cass sessions --current --json` are this conversation echoing the query back.
   - Nothing found → broaden one dimension at a time (drop workspace, widen days, try synonyms or wildcards, switch mode), and say what you tried.
4. **Read.** Expand only the promising hits with `cass view` / `cass expand` using the hit's `source_path` + message index/line (exact flags are in `robot-docs guide`). Keep the context small (`-C 3`) and check the size before pulling large records into context.
5. **Answer.** Summarize what was found. Cite each claim with agent, date, workspace and `source_path` (+ line/message index). Quote the decisive lines. Distinguish what was *decided/done* from what was only *discussed*.
6. **Resume (if asked).** For Claude Code and OpenCode, `cass resume <source_path> --shell` prints the native resume command. cass doesn't support Devin; use `devin --resume <session-id>`, where the id is the last segment of the hit's `source_path` (`…/devin/cli/sessions.db/steady-splash` → `steady-splash`). Give the command to the user rather than running it (it starts an interactive agent, and must run from the session's workspace).

For a handoff to another agent, or a long multi-session summary, prefer `cass pack "<question>" --robot` with token budgets over many separate searches (see `robot-docs guide`, "Pack").

## Readiness problems

Search errors with `maintenance-required`, semantic is unavailable, or results look stale → run `cass health --json` (read-only) and report `recommended_action`/`recommended_commands` to the user. `cass triage --json` gives a fuller diagnosis. Only run the suggested mutating commands with the user's OK.
