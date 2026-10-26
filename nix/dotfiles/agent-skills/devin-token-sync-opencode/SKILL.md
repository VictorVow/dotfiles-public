---
name: devin-token-sync-opencode
description: >-
  Sync the Devin CLI session token to the `devin` provider in all three OpenCode
  installs (opencode, opencode1, opencode2) on both boss and lord-ubuntu. Use
  after `devin auth login` refreshes the token, when an OpenCode devin/ model
  returns auth errors (401, "isn't signed in"), or when the user asks to share /
  copy / refresh the Devin token for OpenCode. Not needed for other providers
  (openrouter, cursor) or for Devin CLI itself.

---

# Devin token → OpenCode sync

## How auth works (don't fix what isn't broken)

All OpenCode Devin access goes through the magpie/fork `devin-auth` plugin (`~/.config/opencode/plugins/devin-auth.js` for v2, `~/.opencode1/config/opencode/plugins/devin-auth.js` for v1), whose `cli` sign-in method stores `metadata.cli: "true"` and **re-reads `credentials.toml` on every request** (`live()` in the plugin). So:

- The only file that matters is `~/.local/share/devin/credentials.toml` — where `devin auth login` writes.
- Saved keys in `auth.json` (v1) and the `credential` table in `opencode.db` (v2) are only fallbacks + account metadata; the `cli` flag makes them self-updating. **Don't hand-edit them** unless the `cli` flag is missing.
- If a stored credential lacks `cli`, it's a stale "browser"-method auth — the fix is `opencode auth login` → "Devin CLI's sign-in", not a token copy.

## Layout

| Host | Consumer | File |
|---|---|---|
| boss | canonical | `~/.local/share/devin/credentials.toml` |
| boss | opencode1 (v1) | `~/.opencode1/data/devin/credentials.toml` — symlink to canonical |
| boss | opencode / opencode2 (v2) | `credential` row in `~/.local/share/opencode/opencode.db`, `methodID: cli` |
| lord-ubuntu | canonical | `~lord/.local/share/devin/credentials.toml` — **copy target** |
| lord-ubuntu | opencode1 (v1) | `~lord/.opencode1/data/devin/credentials.toml` — should be a symlink to canonical (was once a regular file, even a 0-byte one) |
| lord-ubuntu | opencode2 (v2) | `credential` row in `~lord/.local/share/opencode/opencode.db` |

SSH: `ssh lord@lord-ubuntu '<cmd>'` (user `lord`, not `boss`; tailnet ACL).

## Procedure

1. **Confirm the source token is fresh.** `devin auth status` on boss should say "Logged in" *and* the "User / team info" section must not show `Invalid token` — "Logged in" only means the file parses, not that the server accepts it. Also `grep REDACTED ~/.local/share/devin/credentials.toml` must find nothing (see Notes: the nightly scrub once redacted it). If either check fails, stop — the user must `devin auth login` first.
2. **Check the v1 symlink on both hosts** (`ls -la .../data/devin/credentials.toml`):
   - boss: `~/.opencode1/data/devin/credentials.toml` should be a symlink → `~/.local/share/devin/credentials.toml`.
   - lord-ubuntu: same check over ssh. If it's a regular file (or 0 bytes), replace it:
     `ssh lord@lord-ubuntu 'ln -sf ~/.local/share/devin/credentials.toml ~/.opencode1/data/devin/credentials.toml'`
     (v1 resolves `credentials.toml` via `$XDG_DATA_HOME/devin/`; the wrapper sets `XDG_DATA_HOME=~/.opencode1/data`.)
3. **Copy canonical → lord-ubuntu:**
   `cat ~/.local/share/devin/credentials.toml | ssh lord@lord-ubuntu 'umask 077 && cat > ~/.local/share/devin/credentials.toml'`
4. **Check the v2 `cli` flag on both hosts** — `sqlite3 <db> "SELECT value FROM credential WHERE integration_id='devin';"` (db: `~/.local/share/opencode/opencode.db`, same path on lord) — the JSON `value` should contain `"methodID":"cli"` and a truthy `metadata.cli` (`"true"`; older sign-ins saved the boolean `true`, which v2 also accepts). If it does, v2 is done (reads the file live). If it's a `browser` method or `cli` is absent/false, tell the user to run `opencode2 auth login` → "Devin CLI's sign-in" on that host.
5. **Same for v1 `auth.json`** (`~/.opencode1/data/opencode/auth.json`, both hosts): `devin.metadata.cli` must be the **string** `"true"`. v1 only accepts string metadata values: with the boolean `true` (or any non-string value) it silently drops the whole `devin` entry, `opencode1 auth list` no longer shows `devin`, and every request 404s with `Not Found: default backend - 404` (it goes to the plugin's placeholder `https://server.codeium.com/devin/v1` instead of through its fetch). So never set it with `jq '.devin.metadata.cli = true'`; use `jq '.devin.metadata.cli = "true"'` (back the file up first, keep it `600`), then confirm `opencode1 auth list` shows `devin api`. If the entry is missing entirely → `opencode1 auth login` → "Devin CLI's sign-in". Running v1 processes (TUI panes, Orca's `opencode acp`) load auth at startup, so restart them after a change.
6. **Verify:** `ssh lord@lord-ubuntu 'devin auth status'` and `devin auth status` locally both show "Logged in (via Devin)".

## Notes

- `windsurf_api_key` inside the file is the token (`devin-session-token$<jwt>`); keep `api_server_url` etc. — copy the whole file verbatim.
- Permissions: file is `600`; keep it that way (`umask 077` on the remote side does it).
- lord-ubuntu's canonical file can be *newer-looking* than boss's but hold an old session-id — compare md5 or the JWT's `session_id`, not mtime.
- If the user only needs one host, run just that half — the procedure is per-host independent.
- **Token "expires" after ~24h / at 02:00?** That was the nightly `transcript-scrub` timer (02:00, both hosts), not Devin: its targets used to include all of `~/.local/share/devin`, so gitleaks replaced the JWT in `credentials.toml` with `devin-session-token$[REDACTED:jwt]` (file shrinks to ~176 bytes). Fixed 2026-10-26 by narrowing the target to `~/.local/share/devin/cli` in `scripts/security/transcript-common.sh`. If it recurs, check that target list (and `systemctl --user cat transcript-scrub.service` → the deployed store copy) before re-syncing. `credentials.toml.bak.*` files may hold the redacted token too — don't restore from them.
