# Transcript secret scrubbing

AI coding-agent transcripts (Claude Code `~/.claude/projects/*.jsonl`, Codex `~/.config/codex/sessions/**.jsonl`, Gemini, OpenClaw, Copilot CLI, Devin, …) accumulate plaintext secrets whenever an agent reads a `.env`, runs `sops -d`, or cats a key file. cass then mirrors and indexes all of it into `~/.local/share/coding-agent-search/`, making old secrets retrievable by `cass search` forever.

These two scripts scan the transcript stores with gitleaks and rewrite the secrets in place.

## Scripts

| Script | What it does |
| --- | --- |
| `report-exposed-secrets.sh` | Read-only audit. Prints findings grouped by rule × file; exit 1 if any. `--quiet` prints just the JSON report path. |
| `scrub-transcripts.sh` | Rewrites each finding's literal secret value to `[REDACTED:<rule>]` in place (atomic tmp+rename, works on read-only files). `--dry-run` previews. |

```bash
./report-exposed-secrets.sh                 # audit default dirs
./scrub-transcripts.sh --dry-run            # preview rewrites
./scrub-transcripts.sh                      # apply
./scrub-transcripts.sh ~/.claude/projects   # single store
```

Default scan targets: `.claude/projects`, `.config/codex/sessions`, `.gemini`, `.openclaw`, `.copilot/session-state`, `.local/share/devin`, and cass's `raw-mirror` dir.

## Caveats

- **Detection limits.** gitleaks only catches secrets matching a known pattern (API keys, tokens, PEM blocks, age keys). An arbitrary password `sops`-decrypted into a transcript won't match. The report tells you which findings exist; rotate anything sensitive regardless.
- **OpenCode** keeps sessions in sqlite (`~/.local/share/opencode/opencode.db`), not JSONL — not scanned. Scrubbing sqlite rows is possible (`UPDATE … SET content = REPLACE(content, …)`) but deliberately out of scope.
- **Live sessions.** The scrubber skips files modified in the last 5 minutes to avoid racing an agent still writing. Re-run later to catch them.
- **cass mirror.** Scrubbed files get re-indexed by the next `cass-incremental` timer run. `raw-mirror/` holds verbatim copies of sources — it's in the default scan list so it gets scrubbed too, but a mirror copy written between scan and scrub could persist; re-run the report to confirm clean.
- **Not a substitute for rotation.** A secret in a transcript should be considered burned; scrubbing bounds future exposure, it doesn't undo past exposure.

## Config

`gitleaks-scrub.toml` extends gitleaks' default ruleset; add `[allowlist]` paths/stopwords for false positives.
