# Transcript secret scrubbing

AI coding-agent transcripts (Claude Code `~/.claude/projects/*.jsonl` + `history.jsonl` + `file-history/`, Codex `~/.config/codex/sessions/**.jsonl` + `history.jsonl` + sqlite stores, Gemini, OpenClaw, Copilot CLI, Devin, OpenCode v1 sqlite + v2 `session_diff` JSON + `tool-output/` + `log/`, Zed `threads.db`, …) accumulate plaintext secrets whenever an agent reads a `.env`, runs `sops -d`, or cats a key file. cass then mirrors and indexes all of it into `~/.local/share/coding-agent-search/` — the lexical index, the canonical sqlite archive (`agent_search.db`), and `raw-mirror/` verbatim copies — making old secrets retrievable by `cass search` forever.

These two scripts scan all of those stores with gitleaks, rewrite the secrets in place (files) or via per-cell `UPDATE`s (sqlite stores; zed's zstd blobs are decompressed, patched and recompressed), and drop the leaked conversations from the cass archive.

## Scripts

| Script | What it does |
| --- | --- |
| `report-exposed-secrets.sh` | Read-only audit. Prints findings grouped by rule × file/row; exit 1 if any, 2 on scan error. `--quiet` prints just the JSON report path (`$XDG_STATE_HOME/transcript-scrub/last-report.json`, gitleaks `--redact`ed). `--full` forces a rescan. |
| `scrub-transcripts.sh` | Rewrites each finding's literal secret value to `[REDACTED:<rule>]` — files via atomic tmp+rename (works on read-only files), sqlite cells via `UPDATE` per the specs in `transcript_common.SQLITE_SPECS`. Then runs `cass forget` for each scrubbed file and `**/opencode.db*` if any db cells were patched. `--dry-run` previews, `--no-cass` skips the cass step, `--full` rescans everything. |

Both scripts source `transcript-common.sh` (target lists, arg resolution, locking) and import `transcript_common.py` (gitleaks invocation, file/row/conversation dumping, state pruning) — keep the three in sync.

```bash
./report-exposed-secrets.sh                    # audit (incremental)
./report-exposed-secrets.sh --full             # audit everything
./scrub-transcripts.sh --dry-run               # preview rewrites + cass drops
./scrub-transcripts.sh                         # apply
./scrub-transcripts.sh ~/.claude/projects      # single store
./scrub-transcripts.sh ~/.local/share/opencode/opencode.db  # just the v1 db
```

Default file targets: `.claude/projects`, `.claude/history.jsonl`, `.claude/file-history`, `.config/codex/sessions`, `.config/codex/history.jsonl`, `.gemini`, `.openclaw`, `.copilot/session-state`, `.local/share/devin`, opencode v2 `storage/` + `tool-output/` + `log/` dirs (both `~/.local/share/opencode` and `~/.opencode1/data/opencode`). Default sqlite targets: `opencode.db` in both opencode data dirs plus codex `thread_history_1.sqlite`/`state_5.sqlite`/`logs_2.sqlite` and zed `~/.local/share/zed/threads/threads.db` — see `SQLITE_SPECS` in `transcript_common.py` for which columns are scanned. The cass archive (`agent_search.db`) is scanned too — see below.

## Incremental + repeatable

Both scripts share a state file at `$XDG_STATE_HOME/transcript-scrub/state.json` (usually `~/.local/state/transcript-scrub/state.json`).

- **Files**: state maps path → `{mtime, size, findings:[{rule,line}]}`. Unchanged files with no findings are skipped entirely; changed files are re-scanned. Findings from unchanged files carry forward so the report stays complete.
- **Sqlite DBs**: state key `sqlite://<db>` → `{hwm, dirty:[{table,key,col}]}`. `hwm` is a high-water mark on the spec's timestamp column (epoch ms; zed's RFC3339 text is converted); only cells of rows newer than `hwm`, plus cells still marked `dirty`, are dumped and scanned per run. Patched cells become clean. Which tables/columns are scanned is defined per database basename in `transcript_common.SQLITE_SPECS` — unknown sqlite files target nothing.
- **cass archive**: `cass://<db>` → `{hwm, dirty:[source_path]}` over `conversations.last_message_created_at`; `cass://pending` is a dict `{path_or_glob: "exact"|"glob"}` of `cass forget` jobs awaiting a successful run (failures are retried, never silently dropped).
- The literal secret is **never** written to state — only which files/rows were hit and by which rule.

This makes both scripts cheap enough to run on a schedule — only new/changed data actually hits gitleaks. Home Manager wires `scrub-transcripts.sh` to a daily systemd user timer (02:00, `transcript-scrub.timer`, defined in `nix/modules/transcript-scrub.nix`) — it runs before `cass-nightly` (03:00) so forgotten conversations are re-indexed clean in the same nightly window. Logs: `journalctl --user -u transcript-scrub.service`.

## cass archive handling

cass keeps its own copies — `agent_search.db` (canonical archive + FTS index) and `raw-mirror/v1/blobs/` (content-addressed blake3 blobs). Splicing either directly would corrupt cass's verification, so they're handled through cass itself:

- **The archive db is scanned directly.** Each run dumps `messages.content` for conversations newer than the `cass://<db>` high-water mark (on `conversations.last_message_created_at`) plus still-dirty conversations, and gitleaks-scans the dump. This catches secrets in conversations whose source file Claude Code already deleted.
- **Cleanup = `cass forget`, throttled.** The scrubber queues exact `source_path` globs (glob chars escaped, so shared basenames like copilot's `events.jsonl` don't overmatch) for every scrubbed source file, `…/opencode.db/*` when v1 rows were patched, and every conversation the archive scan flagged. cass accepts one `--source-glob` per call and rebuilds its index each time, so a run attempts at most 100 forgets and carries the rest in `cass://pending` for the next run — nothing is dropped, a backlog just takes more than one night.
- **Missing sources are never auto-forgotten.** When a flagged conversation's source file no longer exists, the archive copy is the last remaining record — forgetting deletes it for good, and noisy rules (e.g. `generic-api-key`) can false-positive. Those are listed as `cass review` lines on stderr for a manual `cass forget` instead.
- **Re-indexing.** If the source file still exists, `cass-incremental` re-indexes the now-clean version on its next run; conversations with no remaining source are gone for good (which is the point — the db was the only copy of the secret).
- `--no-cass` skips both the archive scan and the forgets.

## Caveats

- **Detection limits.** gitleaks only catches secrets matching a known pattern (API keys, tokens, PEM blocks, age keys). An arbitrary password `sops`-decrypted into a transcript won't match. Rotate anything sensitive regardless.
- **Sqlite granularity.** The scrubber patches whole scanned cells (`data`/`item_json` blobs, title/preview text, zed's zstd blob). `REPLACE` on a JSON string value is safe (secrets live inside strings), but the cell's other fields are untouched. Stores not scanned: opencode `snapshot/` dirs (bare git object stores — rewriting blobs would corrupt their hashes; the same content already lives in the working repo and `opencode.db`), codex `queue_1`/`goals_1`/`memories_1`/`codex-dev.db` (no free-text transcript columns), `~/.claude/shell-snapshots/` (ephemeral).
- **Live sessions.** Files/DBs modified in the last 5 minutes are skipped to avoid racing a live agent; re-run later to catch them.
- **Partial redaction.** gitleaks reports the secret as the span its regex captured (e.g. `ghp_` + 40 chars). If the file held a longer token, suffix bytes remain — harmless non-secret residue.
- **Not a substitute for rotation.** A secret in a transcript should be considered burned; scrubbing bounds future exposure, it doesn't undo past exposure.

## Config

`gitleaks-scrub.toml` extends gitleaks' default ruleset; add `[allowlist]` paths/stopwords for false positives. `CASS_BIN` / `CASS_DATA_DIR` env vars override the cass binary and data dir if yours differ from the defaults.
