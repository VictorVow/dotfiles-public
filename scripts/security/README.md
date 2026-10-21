# Transcript secret scrubbing

AI coding-agent transcripts (Claude Code `~/.claude/projects/*.jsonl`, Codex `~/.config/codex/sessions/**.jsonl`, Gemini, OpenClaw, Copilot CLI, Devin, …) accumulate plaintext secrets whenever an agent reads a `.env`, runs `sops -d`, or cats a key file. cass then mirrors and indexes all of it into `~/.local/share/coding-agent-search/` — the lexical index, the canonical sqlite archive (`agent_search.db`), and `raw-mirror/` verbatim copies — making old secrets retrievable by `cass search` forever.

These two scripts scan the transcript stores with gitleaks, rewrite the secrets in place, and drop the leaked conversations from the cass archive.

## Scripts

| Script | What it does |
| --- | --- |
| `report-exposed-secrets.sh` | Read-only audit. Prints findings grouped by rule × file; exit 1 if any. `--quiet` prints just the JSON report path. `--full` forces a rescan. |
| `scrub-transcripts.sh` | Rewrites each finding's literal secret value to `[REDACTED:<rule>]` in place (atomic tmp+rename, works on read-only files), then runs `cass forget --source-glob … --apply` for each scrubbed file so the cass archive/index drops the leaked copy. `--dry-run` previews, `--no-cass` skips the cass step, `--full` rescans everything. |

```bash
./report-exposed-secrets.sh                 # audit (incremental)
./report-exposed-secrets.sh --full          # audit everything
./scrub-transcripts.sh --dry-run            # preview rewrites + cass drops
./scrub-transcripts.sh                      # apply
./scrub-transcripts.sh ~/.claude/projects   # single store
```

Default scan targets: `.claude/projects`, `.config/codex/sessions`, `.gemini`, `.openclaw`, `.copilot/session-state`, `.local/share/devin`, and cass's `raw-mirror` dir.

## Incremental + repeatable

Both scripts share a state file at `$XDG_STATE_HOME/transcript-scrub/state.json` (usually `~/.local/state/transcript-scrub/state.json`). It maps each scanned file to `{mtime, size, findings:[{rule,line}]}` — the literal secret is **never** written to state. On subsequent runs:

- Files whose mtime/size are unchanged and have no stored findings are skipped entirely — no gitleaks subprocess.
- Files that changed (or have stored findings) are re-scanned; findings from unchanged files carry forward so the report stays complete.
- After a scrub, a file's `findings` list is cleared except hits skipped as too-short, which stay flagged so the report keeps surfacing them.

This means `report-exposed-secrets.sh` is cheap enough to run interactively or on a schedule — only new/changed transcript files actually hit gitleaks.

## cass archive handling

Scrubbing the *source* file doesn't clean cass's copy — the archive (`agent_search.db`) keeps its indexed copy until the conversation is dropped. The scrubber calls:

```
cass forget --source-glob '**/<basename>' --apply --db <data-dir>/agent_search.db
```

for every scrubbed file. If the file still exists on disk, cass's next `cass-incremental` run re-indexes the now-clean version. `--no-cass` skips this (e.g. when cass isn't installed). `raw-mirror/` is a directory of verbatim file copies — it's in the default targets so those copies get spliced directly.

## Caveats

- **Detection limits.** gitleaks only catches secrets matching a known pattern (API keys, tokens, PEM blocks, age keys). An arbitrary password `sops`-decrypted into a transcript won't match. Rotate anything sensitive regardless.
- **OpenCode** keeps sessions in sqlite (`~/.local/share/opencode/opencode.db`), not JSONL — not scanned. cass `forget` still drops any cass-archived opencode rows when their source glob matches.
- **Live sessions.** Files modified in the last 5 minutes are skipped to avoid racing an agent mid-write; re-run later to catch them.
- **Partial redaction.** gitleaks reports the secret as the span its regex captured (e.g. `ghp_` + 40 chars). If the file held a longer token, suffix bytes remain — harmless non-secret residue.
- **Not a substitute for rotation.** A secret in a transcript should be considered burned; scrubbing bounds future exposure, it doesn't undo past exposure.

## Config

`gitleaks-scrub.toml` extends gitleaks' default ruleset; add `[allowlist]` paths/stopwords for false positives. `CASS_BIN` / `CASS_DATA_DIR` env vars override the cass binary and data dir if yours differ from the defaults.
