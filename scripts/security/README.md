# Transcript secret scrubbing

AI coding-agent transcripts (Claude Code `~/.claude/projects/*.jsonl`, Codex `~/.config/codex/sessions/**.jsonl`, Gemini, OpenClaw, Copilot CLI, Devin, OpenCode v1 sqlite + v2 `session_diff` JSON, …) accumulate plaintext secrets whenever an agent reads a `.env`, runs `sops -d`, or cats a key file. cass then mirrors and indexes all of it into `~/.local/share/coding-agent-search/` — the lexical index, the canonical sqlite archive (`agent_search.db`), and `raw-mirror/` verbatim copies — making old secrets retrievable by `cass search` forever.

These two scripts scan all of those stores with gitleaks, rewrite the secrets in place (files) or via `UPDATE … SET data = replace(data, secret, marker)` (opencode v1 sqlite rows), and drop the leaked conversations from the cass archive.

## Scripts

| Script | What it does |
| --- | --- |
| `report-exposed-secrets.sh` | Read-only audit. Prints findings grouped by rule × file/row; exit 1 if any, 2 on scan error. `--quiet` prints just the JSON report path (`$XDG_STATE_HOME/transcript-scrub/last-report.json`, gitleaks `--redact`ed). `--full` forces a rescan. |
| `scrub-transcripts.sh` | Rewrites each finding's literal secret value to `[REDACTED:<rule>]` — files via atomic tmp+rename (works on read-only files), sqlite rows via `UPDATE`. Then runs `cass forget` for each scrubbed file and `**/opencode.db*` if any db rows were patched. `--dry-run` previews, `--no-cass` skips the cass step, `--full` rescans everything. |

```bash
./report-exposed-secrets.sh                    # audit (incremental)
./report-exposed-secrets.sh --full             # audit everything
./scrub-transcripts.sh --dry-run               # preview rewrites + cass drops
./scrub-transcripts.sh                         # apply
./scrub-transcripts.sh ~/.claude/projects      # single store
./scrub-transcripts.sh ~/.local/share/opencode/opencode.db  # just the v1 db
```

Default file targets: `.claude/projects`, `.config/codex/sessions`, `.gemini`, `.openclaw`, `.copilot/session-state`, `.local/share/devin`, opencode v2 `storage/` dirs (both `~/.local/share/opencode` and `~/.opencode1/data/opencode`). Default sqlite targets: `opencode.db` in both of those opencode data dirs. The cass archive (`agent_search.db`) is scanned too — see below.

## Incremental + repeatable

Both scripts share a state file at `$XDG_STATE_HOME/transcript-scrub/state.json` (usually `~/.local/state/transcript-scrub/state.json`).

- **Files**: state maps path → `{mtime, size, findings:[{rule,line}]}`. Unchanged files with no findings are skipped entirely; changed files are re-scanned. Findings from unchanged files carry forward so the report stays complete.
- **Sqlite DBs**: state key `sqlite://<db>` → `{hwm, dirty:[{table,id}]}`. `hwm` is a high-water mark on the row's `time_updated` (epoch ms); only rows newer than `hwm`, plus rows still marked `dirty`, are dumped and scanned per run. Patched rows become clean.
- **cass archive**: `cass://<db>` → `{hwm, dirty:[source_path]}` over `conversations.last_message_created_at`; `cass://pending` holds `cass forget` globs awaiting a successful run (failures are retried, never silently dropped).
- The literal secret is **never** written to state — only which files/rows were hit and by which rule.

This makes both scripts cheap enough to run on a schedule — only new/changed data actually hits gitleaks. Home Manager wires `scrub-transcripts.sh` to a daily systemd user timer (02:00, `transcript-scrub.timer`, defined in `nix/modules/transcript-scrub.nix`) — it runs before `cass-nightly` (03:00) so forgotten conversations are re-indexed clean in the same nightly window. Logs: `journalctl --user -u transcript-scrub.service`.

## cass archive handling

cass keeps its own copies — `agent_search.db` (canonical archive + FTS index) and `raw-mirror/v1/blobs/` (content-addressed blake3 blobs). Splicing either directly would corrupt cass's verification, so they're handled through cass itself:

- **The archive db is scanned directly.** Each run dumps `messages.content` for conversations newer than the `cass://<db>` high-water mark (on `conversations.last_message_created_at`) plus still-dirty conversations, and gitleaks-scans the dump. This catches secrets in conversations whose source file Claude Code already deleted.
- **Cleanup = `cass forget`, batched.** The scrubber queues exact `source_path` globs (glob chars escaped, so shared basenames like copilot's `events.jsonl` don't overmatch) for every scrubbed source file, `…/opencode.db/*` when v1 rows were patched, and every conversation the archive scan flagged. Failed or skipped forgets persist in state under `cass://pending` and are retried on the next run.
- **Re-indexing.** If the source file still exists, `cass-incremental` re-indexes the now-clean version on its next run; conversations with no remaining source are gone for good (which is the point — the db was the only copy of the secret).
- `--no-cass` skips both the archive scan and the forgets.

## Caveats

- **Detection limits.** gitleaks only catches secrets matching a known pattern (API keys, tokens, PEM blocks, age keys). An arbitrary password `sops`-decrypted into a transcript won't match. Rotate anything sensitive regardless.
- **opencode v1 granularity.** The scrubber patches whole `data` JSON blobs in `message`/`part` rows. `REPLACE` on a JSON string value is safe (secrets live inside strings), but the row's other fields are untouched.
- **Live sessions.** Files/DBs modified in the last 5 minutes are skipped to avoid racing a live agent; re-run later to catch them.
- **Partial redaction.** gitleaks reports the secret as the span its regex captured (e.g. `ghp_` + 40 chars). If the file held a longer token, suffix bytes remain — harmless non-secret residue.
- **Not a substitute for rotation.** A secret in a transcript should be considered burned; scrubbing bounds future exposure, it doesn't undo past exposure.

## Config

`gitleaks-scrub.toml` extends gitleaks' default ruleset; add `[allowlist]` paths/stopwords for false positives. `CASS_BIN` / `CASS_DATA_DIR` env vars override the cass binary and data dir if yours differ from the defaults.
