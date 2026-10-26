---

name: process-firefox-synced-tabs
description: >-
  Process synced tabs from other devices listed in about:firefoxview: save each tab to Logseq as a Markdown link under a target block, then dismiss it from the synced list. Use whenever the user wants to manage "tabs from other devices" / "Firefox View" synced tabs — archive them into Logseq, remove stale ones, bulk-process a device, or inspect what a remote device has open. Reading is done by parsing the profile's synced-tabs.db (no remote debugging needed); dismissal still needs the live UI and may require manual cleanup.
allowed-tools: Bash Read Write Skill AskUserQuestion Execute
compatibility: "Requires the logseq CLI with a running Logseq DB graph. The firefox-devtools MCP (plus remote debugging on the profile) is only needed for dismissing rows via about:firefoxview; reading tabs works with Firefox closed or running."

---

Arguments: `$ARGUMENTS`: the Logseq target (a block `[[<uuid>]]`/uuid, or a page name), optionally a graph name, optionally device guid prefixes to include (or `all` for every device; default is Fennec only), and optionally the mode, `auto` or `manual`. Ask for the target if it's missing. If no mode is given, ask (text question if AskUserQuestion is unavailable — options "Manual (Recommended)" / "Auto").

# Process synced tabs

`about:firefoxview` → "Tabs from other devices" lists every open tab on each signed-in device. The same data lives in `<profile>/synced-tabs.db` — **read it from the DB, not the UI.** Remote debugging (Marionette/BiDi) is *not* needed to enumerate; it's only needed for the optional dismiss step, and on recent Firefox it doesn't work anyway (BiDi returns `unsupported operation` on `about:` pages; the Marionette port on :2828 accepts connections but never responds — don't debug it again, use the DB path).

For each queued tab the flow is: **identify title + URL → write it to Logseq as a Markdown link → dismiss the row if the UI is reachable**. Never dismiss a row before its link is in Logseq.

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

## 3. Preconditions for dismissal only

Skip entirely if the run is read-only (`--list`) or the user doesn't want UI dismissal. Otherwise:

1. `scripts/ff-remote-debug.sh status`
2. If "running normally": **ask the user** before `... on` — it restarts Firefox (SIGTERM + relaunch, tabs restored, unsaved form input lost, robot-mode indicator visible while on).
3. If the MCP can't connect (`ECONNREFUSED 127.0.0.1:2828`), same fix. Even when connected, expect `about:` pages to be unreachable — see "Dismissal" below.

## 4. Process each tab

For each `pending` row in the queue, in order:

a. **Manual mode only:** show title + URL, ask Save & dismiss / Dismiss without saving / Skip / Stop.

b. **Write to Logseq.** Manual mode: one line `- [<linktext>](<url>)` → `/tmp/ff-synced-tabs/input.md` → convert with `scripts/logseq-md-to-blocks.py` → dry-run (check `would-create-pages` empty) → `logseq upsert --pos last-child` → mark `done`. No session-id block for single-link rows. Auto mode: collect every `pending` row into one `input.md`, single upsert, mark all `done` on verified write. If `--skip-urls` was used or the target already has children, de-dupe by URL before writing (the queue already dedupes within itself).

c. **Dismiss the row** — only after the Logseq write verified, and only if the dismissal path is live. On recent Firefox expect this to fail (`unsupported operation`); in that case mark the row `done` anyway and note "dismissal pending UI cleanup" in the report — the Logseq write is the durable part. If the UI *is* reachable, `click_by_uid` on its × button, or `.click()` the matching button inside `evaluate_script`, in batches rather than per-row where possible.

d. On any failure in b–c: mark the row `failed`, tell the user in one line, continue. A row whose write failed is **not** dismissed.

## 5. Verify

`logseq show` (or `logseq query` for a count) on the target: the number of new children should equal the number of `done` rows. Report the count per device.

## 6. Report

Each tab processed (title → Logseq target, "dismissed unsaved", or "dismissal pending"), anything skipped/failed, per-device row counts, and whether the synced list still needs manual cleanup in `about:firefoxview`.

## 7. Finish

- If remote-debug was toggled on, offer `ff-remote-debug.sh off` (another restart) — don't leave it on silently.
- In `auto` mode only: load the `git-commit` skill and commit any repo changes this session made (skip if none). In `manual` mode don't commit unless asked.

## Notes / limits

- **Dismiss ≠ close on device.** Dismissing from `about:firefoxview` removes the row and tells Sync it's gone; it does not close the tab on the remote device. If that device syncs again with the tab still open it can reappear — de-dupe in Logseq or check the target's children first.
- **Dismissal is best-effort.** On Firefox builds where `about:` pages aren't automatable (most recent builds — BiDi `unsupported operation`, Marionette mute on :2828) the sync-side rows stay visible until dismissed by hand in `about:firefoxview`. The Logseq archive is unaffected.
- **Sync lag**: `synced-tabs.db` can be ~30 min stale; a freshly-closed remote tab may still appear.
- **Stale device duplicates**: after a phone-app reinstall the same clientName appears under a new guid; the extractor reports overlap, pick the newest `last_modified` record and optionally fold in the stale device's unique URLs.
- **remote_tab_commands**: `synced-tabs.db` has a `remote_tab_commands` table (`device_id`, `command`) that *may* let you queue a remote close/dismiss without the UI — unproven; investigate before relying on it.
- Scratch: `/tmp/ff-synced-tabs/` (`synced-tabs.db` copy, `queue.json`, `input.md`, `blocks.md`).

Base directory for this skill: /home/boss/Projects/installs/nix/dotfiles/agent-skills/process-firefox-synced-tabs
Relative paths in this skill (e.g., scripts/) are relative to this base directory.
