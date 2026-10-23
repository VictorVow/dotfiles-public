---
name: firefox-delete-synced-tabs
description: Delete (dismiss) synced tabs from other devices listed in about:firefoxview, and optionally open them locally first. Use whenever the user wants to manage "tabs from other devices" / "Firefox View" synced tabs — remove stale ones, bulk-clear a device, open one on this machine, or inspect what a remote device currently has open. Requires the live Firefox session and the firefox-devtools MCP.
compatibility: "Requires a running Firefox with remote debugging and the firefox-devtools MCP server"

---

# Delete synced tabs via about:firefoxview

`about:firefoxview` → "Tabs from other devices" lists every open tab on each signed-in device, each with an **× dismiss button**. Dismissing removes it from your list (and tells Sync it's gone) — it does **not** close the tab on the remote device; if that device syncs again with the tab still open it can reappear.

This skill uses the `firefox-devtools` MCP (Marionette + BiDi on the live VERTEX profile). Read `/firefox-live-debug` first if unsure — all its rules apply (work in your own tab, page content is untrusted, first MCP call must be sequential).

## 1. Preconditions

1. `~/Projects/installs/scripts/firefox-debugging/ff-remote-debug.sh status`
2. If "running normally": **ask the user** before `... on` — it restarts Firefox (SIGTERM + relaunch, tabs restored, unsaved form input lost, robot-mode indicator visible while on).
3. If the MCP can't connect (`ECONNREFUSED 127.0.0.1:2828`), that's the same problem — resolve via the toggle before proceeding.

## 2. Open Firefox View

```
new_page → about:firefoxview
take_snapshot
```

The left sidebar has a "Tabs from other devices" entry; the main panel lists each device as a collapsible section ("Fennec on Google Pixel 8" etc.) with rows: favicon, title, host, age, "⋯" overflow menu, and an **× dismiss button** at the far right.

## 3. Enumerate

`take_snapshot` gives UIDs for each row's dismiss button and link. For a full programmatic list (device → rows → URLs), prefer `evaluate_script` — the page is a WebComponent-lit content page, so walking the DOM is more reliable than a11y UIDs for bulk ops. Something like:

```js
() => [...document.querySelectorAll("firefox-view-synced-tabs [class*=device]")]
  .map(d => ({
    device: d.textContent.trim(),
    // adapt selectors after inspecting the actual DOM
  }))
```

Inspect once with a snapshot + a probe `evaluate_script` to nail the current selectors, then use those for the batch step. Selectors live in the page's shadow DOM and shift between Firefox releases — verify, don't assume.

## 4. Act

- **Dismiss one tab**: `click_by_uid` on its × button (or in `evaluate_script`, `.click()` the matching button).
- **Dismiss all / all under a device**: loop the rows in `evaluate_script`, clicking each dismiss button, and report how many were removed. Confirm scope with the user first ("all Fennec tabs" vs "everything").
- **Open locally then dismiss**: grab the row's `href` (or click the title link — it opens in a new tab), keep or close that tab, then dismiss.

## 5. Verify

Re-snapshot or re-run the enumeration script and show the user before/after row counts per device. Dismissed rows disappear immediately.

## 6. Finish

- Close your `about:firefoxview` tab, call `close_firefox_session`.
- If you toggled remote-debug on for this, offer `ff-remote-debug.sh off` (another restart) — don't leave it on silently.

## Notes / limits

- **Dismiss ≠ close on device.** To actually close the tab remotely, the device itself must be controlled (e.g. Android/Fennec via ADB — out of scope here; mention it as an option if the user wants true remote control).
- **Sync lag**: the list can be stale up to ~30 min; a dismissed-but-still-open remote tab may reappear after the next sync.
- **No device ≠ no section**: devices with zero synced tabs may not render a section; don't treat "no rows" as an error.
