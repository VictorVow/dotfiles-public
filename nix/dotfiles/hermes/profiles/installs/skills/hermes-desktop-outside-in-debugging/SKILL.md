---
name: hermes-desktop-outside-in-debugging
description: "Outside-in debugging of the packaged Hermes desktop app."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [desktop, electron, debugging, gateway, tickets, self-inspection]
    related_skills: [inspecting-hermes-desktop-dom, hermes-agent, systematic-debugging]
---

# Hermes desktop: outside-in debugging (packaged runs)

## When to Use

- The user reports a desktop-app malfunction (pane won't load, endless spinner,
  a feature broken only for one profile) on a **packaged run** — where no CDP
  port exists.
- You need to verify whether a Hermes gateway/backend is healthy without the
  desktop app in the loop.
- A screenshot was attached but vision analysis is unavailable.

Don't use for dev-server runs (CDP inspection via `inspecting-hermes-desktop-dom`
is strictly better there), or for perf/heap profiling.

## Procedure

Work in this order:

## 1. See what the user sees: OCR the screenshot

If a screenshot was attached and vision analysis is unavailable, run tesseract
on it instead of guessing:

```bash
tesseract <image.png> out --psm 11   # sparse-text mode; also try default psm
head out.txt
```

OCR recovers tab labels, headings, and error banners. It cannot see spinners or
blank panels — pair the (lack of) text with the user's description, and ask one
targeted question when the failure mode forks the diagnosis (e.g. spinner vs
blank vs error text, and which profile's chat).

## 2. Read the logs that answer

- `~/.hermes/logs/desktop.log` — main-process log.
  - `[hermes:api GET /api/...] Error: <reason>` — the backend call the renderer
    made and why it failed. An error storm here (e.g. `Noncanonical gateway
    profile`) means ticket minting is failing for every call.
  - `[gateway-route win=main] ... profile=<p>` lines show which profile is
    primary and which is `primary-shared`.
  - The renderer console is forwarded only on warn/error — a quiet log does
    NOT mean the pane is healthy.
- `~/.hermes/logs/{errors,gateway}.log` and per-profile
  `~/.hermes/profiles/<name>/logs/{gateway,agent,errors}.log` — under a
  multiplexing gateway the host process writes the shared profiles' logs into
  their profile dirs too.

## 3. Exercise the backend exactly as the desktop does

The desktop authenticates each `hermes:api` HTTP call with a short-lived ticket
minted over the owner-only control socket. Reproduce this to decide whether the
backend is healthy (if your direct call succeeds, the bug is client-side):

1. Connect a unix socket to `$HERMES_HOME/gateway.sock` and send
   `{"protocol":1,"id":1,"verb":"identify","params":{}}` — the result
   carries `instance_id`, `api_origin` (the HTTP host:port), and
   `served_profiles`.
2. Send verb `session-ticket` with params **exactly**
   `{profile_id, instance_id, purpose, scope}` — extra keys (e.g. a `url`) are
   rejected as `invalid bootstrap parameters`; a stale `instance_id` is
   `stale runtime instance`. Pass the profile home path
   (e.g. `/home/boss/.hermes/profiles/<name>`) as `profile_id`.
3. Call `http://<api_origin>/api/...` with header
   `x-hermes-gateway-ticket: <ticket>` — `Authorization: Bearer` answers 401.
4. A `purpose: native-http, scope: profile` ticket gets
   `403 profile_scope_mismatch` on all-profiles routes unless the URL carries
   `?profile=<name>`. Mint a fresh ticket right before use — they expire in
   ~30 seconds.

The native session WebSocket (`<api_origin>/api/ws?native_dial=unminted`)
takes the ticket as a Sec-WebSocket-protocol entry —
`['hermes-gateway-v1', 'hermes-gateway-ticket.<ticket>']` (interactive purpose,
host scope) — and then speaks JSON-RPC. The gateway's native WS has its own
method table (`session.mutate`, `session.control`, `session.stats`, ...);
TUI-only methods like `session.workspace.move` answer `unknown method` there.
For live-session operations use `session.mutate` (e.g. `operation: 'workspace'`
is the "Move to project" re-anchoring; params must be exactly
`{session_id, request_id, expected_revision, operation, payload}` plus
`expected_generation` for policy operations).

Two quirks when driving `session.mutate` on a **live session from inside that
same session's agent** (e.g. moving your own chat's workspace):

- `session_busy` while the session's turn runs — and your own turn is always
  running while you act, so a direct one-shot call can never commit. Launch a
  detached retry loop (every ~5 s) and it commits the moment the turn ends.
- `expected_revision`/`expected_generation` bump **every turn**, so hardcoding
  them gets `revision_conflict` on the first retry. Read the live values from
  the profile's store on every attempt instead:
  `sqlite3 file:<profile home>/state.db?mode=ro "SELECT runtime_revision,
  runtime_generation FROM sessions WHERE id='<sid>'"` (sid is the short
  `local-…` id, not the `agent:<profile>:local:dm:<sid>` session_key).

### session.mutate against a live session — the three refusals

- **Key by sid, not session_key**: session controls take the bare sid
  (`local-<hex>`); passing the gateway's `agent:<profile>:local:dm:<sid>`
  session_key answers `4001 not_found`. Get the sid from
  `/api/profiles/sessions?profile=<name>` or the sid column of the profile's
  `state.db`.
- **`session_busy`**: the mutation refuses while that session's turn is running
  — so an agent can never commit it on its own session mid-turn. Run a detached
  retry loop (terminal `background=true`) that retries every few seconds and
  lands the commit the moment the turn goes idle.
- **`revision_conflict` / `stale_generation`**: `runtime_revision` and
  `runtime_generation` (in the profile's `state.db`, `sessions` table) bump on
  EVERY turn — read them fresh immediately before each attempt. A value read
  earlier in the session is already stale after one more turn. The refusal's
  `error.data` echoes the current `revision`/`execution_generation`; or re-read
  `state.db` read-only (`sqlite3 connect('file:...state.db?mode=ro', uri=True)`).
- `session.stats` (usage) and `session.events.since` (events) do NOT return the
  revision — don't hunt for it over RPC; read `state.db`.

## 4. Multi-profile mental model

- One multiplexing gateway — usually the default profile's process — serves
  every profile; check `~/.hermes/gateway_state.json` → `served_profiles`.
- Served secondary profiles have **no** `gateway.sock` in their own home — that
  is normal, not the bug. The desktop reaches them through the host home's
  control socket (its `control_home` fallback). Don't try to create a socket or
  pointer in the secondary home.

## Pitfalls

- **Test the backend before reading the renderer bundle.** Minified-javascript
  archaeology is slow and error-prone; a two-line ticket + curl either clears
  the backend or pins the fault to it. Only read `dist/assets/*.js` when the
  backend test succeeds and you need to find which client path is taken.
- **Never dump whole minified bundles to stdout** — grep for the specific
  endpoint/method string and print only a small slice around it; a bundle dump
  buries the context window.
- **Ask one targeted clarify when the failure mode forks the fix.** "Spinner
  forever, only the secondary profile's chat" points at client-side profile
  routing; "error banner everywhere" points at the backend.
- **The Files/Projects pane follows the session's workspace (cwd), not the
  project it was later switched into.** A session that started before its
  project existed stays grouped under Home until explicitly moved — fix with
  the desktop's "Move to project" menu or the `session.mutate` workspace RPC,
  not by re-switching projects.
- **New chats get their workspace from the profile's `terminal.cwd`, which
  unset inherits the Desktop launch dir** — so fresh tabs open at the launch
  dir even after every existing session was moved. Fix at the root with
  `hermes --profile <name> config set terminal.cwd <repo>` (never hand-edit
  the live config.yaml); a named profile's configured value beats the
  inherited cwd, and the `+` tab follows immediately after.
- **Don't run gateway-control scripts without fast user approval** — raw socket
  + JSON-RPC scripts look scary to approval gates; keep them short and explain
  what they do, or prefer the equivalent desktop UI action when it exists.
- **Launch helper scripts with terminal `background=true`, never nohup** — the
  terminal tool refuses shell-level wrappers (`nohup ... &`), and a wrapper
  command that also carried your only `chmod +x` dies unexecuted, so the next
  run fails with `Permission denied` (exit 126). Run `chmod +x` as its own
  command first, then `bash script.sh` with `background=true, notify=true`.
