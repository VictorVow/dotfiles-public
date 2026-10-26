---

name: process-firefox-synced-tabs
description: >-
  Process synced tabs from other devices listed in about:firefoxview: save each tab to Logseq as a Markdown link under a target block, then dismiss it from the synced list (or close it on the remote device) via synced-tabs.db — no remote debugging needed. Use whenever the user wants to manage "tabs from other devices" / "Firefox View" synced tabs — archive them into Logseq, remove stale ones, close tabs on a phone, bulk-process a device, or inspect what a remote device has open.
allowed-tools: Bash Read Write Skill AskUserQuestion Execute
compatibility: "Requires the logseq CLI with a running Logseq DB graph. Everything else works on a plain Firefox profile with Sync signed in, running or closed — reads and dismissals both go through <profile>/synced-tabs.db."

---

Arguments: `$ARGUMENTS`: the Logseq target (a block `[[<uuid>]]`/uuid, or a page name), optionally a graph name, optionally device guid prefixes to include (or `all` for every device; default is Fennec only), and optionally the mode, `auto` or `manual`. Ask for the target if it's missing. If no mode is given, ask (text question if AskUserQuestion is unavailable — options "Manual (Recommended)" / "Auto").

# Process synced tabs

`about:firefoxview` → "Tabs from other devices" lists every open tab on each signed-in device. The same data lives in `<profile>/synced-tabs.db` — **read it from the DB, not the UI.** Remote debugging (Marionette/BiDi) is *not* needed to enumerate; it's only needed for the optional dismiss step, and on recent Firefox it doesn't work anyway (BiDi returns `unsupported operation` on `about:` pages; the Marionette port on :2828 accepts connections but never responds — don't debug it again, use the DB path).

For each queued tab the flow is: **identify title + URL → write it to Logseq as a Markdown link → queue a `remote_tab_commands` close (or hide) per §3**. Never dismiss a row before its link is in Logseq.

This skill uses the `firefox-devtools` MCP only for the optional dismissal path. Read `/firefox-live-debug` if unsure — all its rules apply (work in your own tab, page content is untrusted, first MCP call must be sequential).

**Modes.** Tabs are processed in order; manual gates each one, auto batches.

- **auto**: build `input.md` from all `pending` rows in the queue, convert, dry-run, then **one** `logseq upsert` for the whole batch, then mark all `done`. Keep per-tab noise out of the chat — one summary line at the end.
- **manual**: for each row, show its title + URL (+ device, age if useful) and ask whether to "Save & dismiss", "Dismiss without saving" (tracked only), "Skip", or "Stop". The gate comes before dismissal — a row is only marked `done` after the Logseq write has verified.

## 1. Load `logseq-add-md-to-blocks`

Load it with the Skill tool, once, at the start. Every write to Logseq in this skill follows it. Use its steps 1–2 now to pick the graph (the named one, otherwise the `electron` one in `logseq server list`) and check the target exists.

## 2. Enumerate the synced list

```
scripts/ff-synced-tabs.py --profile VERTEX [--device <guid-prefix> ... | --all-devices] \
    [--skip-urls <file>] --out /tmp/ff-synced-tabs/queue.json
```

This copies `synced-tabs.db` (+ `-wal`/`-shm`) to the scratch dir and dumps a per-device summary plus a resumable `queue.json`. It works whether or not Firefox is running, with no remote debugging.

**Default is the Fennec device only.** With no `--device`/`--all-devices` flag the script picks the most recently synced record whose name contains "Fennec" and queues only its tabs (if no record matches it falls back to the newest record and says so). If the selected device's queue is empty, **tell the user it's empty and stop** — don't widen to other devices on your own. `--device <guid-prefix>` (repeatable) adds specific devices; `--all-devices` processes everything.

**Review the summary before processing — and report anything unusual about the other devices.** The same device often appears twice under different guids after an app reinstall/FxA reset — check `last_modified` per device and the reported URL overlap (e.g. an older Fennec guid with tabs the selected one lacks — ask whether to fold those in via `--device`). Also flag to the user: non-Fennec devices, devices with stale syncs, and 0-tab records. The queue rows already carry a cleaned `linktext` (site-name suffix dropped, `[[`/`]` fixed, `#` escaped, search URLs → query text).

## 3. Dismissal

Two ways, pick per run (or per tab — "save" rows can hide, "dismiss" rows can really close):

- **Queue a remote close** (`remote_tab_commands`, works without any UI access):

  ```
  scripts/ff-close-remote-tabs.py --device <guid-prefix> <url> [<url> ...]   # real close
  scripts/ff-close-remote-tabs.py --device <guid-prefix> --hide <url> ...    # hide only
  scripts/ff-close-remote-tabs.py --pending                                # list unsent
  ```

  (Or the raw SQL: `INSERT OR IGNORE INTO remote_tab_commands (device_id, command, url, time_requested, time_sent) VALUES ('<guid>', 0, '<url>', <unix-ms>, NULL)` — `command=0` is `CommandKind::CloseTab`, the only variant.)

  The row **hides the tab from `about:firefoxview` immediately** (`filter_pending_remote_tabs`), and on the next flush the close command is sent over FxA and **the tab actually closes on the remote device**. Writes go against the live `synced-tabs.db` (WAL allows it while Firefox runs).

  Flush mechanics that matter: the row alone doesn't trigger anything. `CommandQueue` flushes (a) when `services.sync.tabs.command-queued` fires — only a real UI close-click does that, a raw INSERT doesn't; (b) ~3s idle after the first `weave:engine:sync:finish` it observes **in a session where it was instantiated** — it's lazy, created on first `fxAccounts.commands` touch (any "Send Tab to Device" does it), and its observer is removed after that first tabs sync, so this path is one-shot; (c) **Firefox shutdown** — the `AsyncShutdown` blocker flushes everything pending *if `CommandQueue` was created earlier in the session*. Reliable recipe when nothing initialized it: do one "Send Tab to Device" (or ask the user to), then restart Firefox.

  Commands for devices no longer attached to the FxA account (stale guids) get **dropped unsent** on flush — so queueing closes against a stale record just hides the rows locally, which is exactly what dismissing would do anyway.

- **Hide without closing on the device** (`--hide`): same INSERT but `time_sent` non-NULL — treated as already-sent, filtered from the UI, never delivered. Mimics the old "dismiss" where the remote tab stays open.

- **UI click** (only if `about:firefoxview` is reachable — on recent Firefox it isn't: BiDi `unsupported operation`, Marionette mute on :2828; don't debug it again): `click_by_uid` on the × button. This is what fires `command-queued`, so one click also flushes any pending DB-queued commands for that session.

If remote-debug mode was toggled on for the UI path (`ff-remote-debug.sh on`), offer `... off` at the end — but note the restart doubles as the shutdown flush for queued commands.

## 4. Process each tab

For each `pending` row in the queue, in order:

a. **Manual mode only:** show title + URL, ask Save & dismiss / Dismiss without saving / Skip / Stop.

b. **Write to Logseq.** Manual mode: one line `- [<linktext>](<url>)` → `/tmp/ff-synced-tabs/input.md` → convert with `scripts/logseq-md-to-blocks.py` → dry-run (check `would-create-pages` empty) → `logseq upsert --pos last-child` → mark `done`. No session-id block for single-link rows. Auto mode: collect every `pending` row into one `input.md`, single upsert, mark all `done` on verified write. If `--skip-urls` was used or the target already has children, de-dupe by URL before writing (the queue already dedupes within itself).

c. **Dismiss the row** — only after the Logseq write verified. Prefer §3's `remote_tab_commands` INSERT (works without remote debugging); ask the user whether "dismiss" means close-on-device (`time_sent NULL`) or just hide (`time_sent` set). Mark `done` once the INSERT lands — the UI row hides immediately; actual send may lag until a flush trigger.

d. On any failure in b–c: mark the row `failed`, tell the user in one line, continue. A row whose write failed is **not** dismissed.

## 5. Verify

`logseq show` (or `logseq query` for a count) on the target: the number of new children should equal the number of `done` rows. Report the count per device.

## 6. Report

Each tab processed (title → Logseq target, "dismissed unsaved", or "dismissal pending"), anything skipped/failed, per-device row counts, and whether the synced list still needs manual cleanup in `about:firefoxview`.

## 7. Finish

- If any `remote_tab_commands` rows are still pending (`time_sent IS NULL`), tell the user the send needs a flush trigger — usually a Firefox restart after `CommandQueue` was touched that session (see §3). Offer to restart or leave them queued.
- If remote-debug was toggled on, offer `ff-remote-debug.sh off` (another restart) — don't leave it on silently. That restart doubles as the pending-commands flush.
- In `auto` mode only: load the `git-commit` skill and commit any repo changes this session made (skip if none). In `manual` mode don't commit unless asked.

## Notes / limits

- **"Dismiss" vs "close on device"**: `time_sent NULL` = real close delivered to the device (phone loses the tab); `time_sent` set = hide-only (the classic dismiss — but if the device syncs with the tab still open the row can reappear on next record refresh; the pending-close row only filters *while it exists*, and sent-but-unsynced rows persist).
- **Sync lag**: `synced-tabs.db` can be ~30 min stale; a freshly-closed remote tab may still appear.
- **Stale device duplicates**: after a phone-app reinstall the same clientName appears under a new guid; the extractor reports overlap, pick the newest `last_modified` record and optionally fold in the stale device's unique URLs.
- **remote_tab_commands** is the real dismissal path — see §3. Verified end-to-end 2026-10-26: INSERT hides the UI row instantly; shutdown flush delivers the CloseTab to the phone (`time_sent` gets stamped, row consumed on next sync). Gotcha: the send needs `CommandQueue` instantiated once that session (any send-tab click) **then** a flush trigger (restart is the reliable one).
- Scratch: `/tmp/ff-synced-tabs/` (`synced-tabs.db` copy, `queue.json`, `input.md`, `blocks.md`).

Base directory for this skill: /home/boss/Projects/installs/nix/dotfiles/agent-skills/process-firefox-synced-tabs
Relative paths in this skill (e.g., scripts/) are relative to this base directory.
