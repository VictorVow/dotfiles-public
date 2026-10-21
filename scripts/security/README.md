# Transcript secret scrubbing

AI coding-agent transcripts (Claude Code `~/.claude/projects/*.jsonl`, Codex `~/.config/codex/sessions/**.jsonl`, Gemini, OpenClaw, Copilot CLI, Devin, OpenCode v1 sqlite + v2 `session_diff` JSON, …) accumulate plaintext secrets whenever an agent reads a `.env`, runs `sops -d`, or cats a key file. cass then mirrors and indexes all of it into `~/.local/share/coding-agent-search/` — the lexical index, the canonical sqlite archive (`agent_search.db`), and `raw-mirror/` verbatim copies — making old secrets retrievable by `cass search` forever.

These two scripts scan all of those stores with gitleaks, rewrite the secrets in place (files) or via `UPDATE … SET data = replace(data, secret, marker)` (opencode v1 sqlite rows), and drop the leaked conversations from the cass archive.

## Scripts

| Script | What it does |
| --- | --- |
| `report-exposed-secrets.sh` | Read-only audit. Prints findings grouped by rule × file/row; exit 1 if any. `--quiet` prints just the JSON report path. `--full` forces a rescan. |
| `scrub-transcripts.sh` | Rewrites each finding's literal secret value to `[REDACTED:<rule>]` — files via atomic tmp+rename (works on read-only files), sqlite rows via `UPDATE`. Then runs `cass forget` for each scrubbed file and `**/opencode.db*` if any db rows were patched. `--dry-run` previews, `--no-cass` skips the cass step, `--full` rescans everything. |

```bash
./report-exposed-secrets.sh                    # audit (incremental)
./report-exposed-secrets.sh --full             # audit everything
./scrub-transcripts.sh --dry-run               # preview rewrites + cass drops
./scrub-transcripts.sh                         # apply
./scrub-transcripts.sh ~/.claude/projects      # single store
./scrub-transcripts.sh ~/.local/share/opencode/opencode.db  # just the v1 db
```

Default file targets: `.claude/projects`, `.config/codex/sessions`, `.gemini`, `.openclaw`, `.copilot/session-state`, `.local/share/devin`, opencode v2 `storage/` dirs (both `~/.local/share/opencode` and `~/.opencode1/data/opencode`), and cass's `raw-mirror`. Default sqlite targets: `opencode.db` in both of those opencode data dirs.

## Incremental + repeatable

Both scripts share a state file at `$XDG_STATE_HOME/transcript-scrub/state.json` (usually `~/.local/state/transcript-scrub/state.json`).

- **Files**: state maps path → `{mtime, size, findings:[{rule,line}]}`. Unchanged files with no findings are skipped entirely; changed files are re-scanned. Findings from unchanged files carry forward so the report stays complete.
- **Sqlite DBs**: state key `sqlite://<db>` → `{hwm, dirty:[{table,id}]}`. `hwm` is a high-water mark on the row's `time_updated` (epoch ms); only rows newer than `hwm`, plus rows still marked `dirty`, are dumped and scanned per run. Patched rows become clean.
- The literal secret is **never** written to state — only which files/rows were hit and by which rule.

This makes both scripts cheap enough to run on a schedule — only new/changed data actually hits gitleaks.

## cass archive handling

Scrubbing the *source* doesn't clean cass's copy — `agent_search.db` keeps its indexed copy until the conversation is dropped. The scrubber calls:

```
cass forget --source-glob '**/<basename>' --apply --db <data-dir>/agent_search.db
cass forget --source-glob '**/opencode.db*' --apply --db …   # if any v1 rows were patched
```

If the file still exists on disk, cass's next `cass-incremental` run re-indexes the now-clean version. `--no-cass` skips this. `raw-mirror/` is a directory of verbatim file copies — it's in the default targets so those copies get spliced directly.

## Caveats

- **Detection limits.** gitleaks only catches secrets matching a known pattern (API keys, tokens, PEM blocks, age keys). An arbitrary password `sops`-decrypted into a transcript won't match. Rotate anything sensitive regardless.
- **opencode v1 granularity.** The scrubber patches whole `data` JSON blobs in `message`/`part` rows. `REPLACE` on a JSON string value is safe (secrets live inside strings), but the row's other fields are untouched.
- **Live sessions.** Files/DBs modified in the last 5 minutes are skipped to avoid racing a live agent; re-run later to catch them.
- **Partial redaction.** gitleaks reports the secret as the span its regex captured (e.g. `ghp_` + 40 chars). If the file held a longer token, suffix bytes remain — harmless non-secret residue.
- **Not a substitute for rotation.** A secret in a transcript should be considered burned; scrubbing bounds future exposure, it doesn't undo past exposure.

## Config

`gitleaks-scrub.toml` extends gitleaks' default ruleset; add `[allowlist]` paths/stopwords for false positives. `CASS_BIN` / `CASS_DATA_DIR` env vars override the cass binary and data dir if yours differ from the defaults.


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
