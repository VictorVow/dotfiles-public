# Firefox debugging toolkit

Scripts for diagnosing a misbehaving Firefox profile — freezes, runaway memory, blank extension icons / empty Sidebery panel, repeated extension-process crashes. Built during the 2026-07-03 VERTEX incident, where GeoSpoof 1.22.14 called `tabs.query` ~25×/sec against a ~1,900-tab session, pegging the parent main thread and OOM-crashing the shared extension process.

All scripts default to the `VERTEX` profile; pass `-p NAME` for another profile under `~/.mozilla/firefox/`. They only need bash, ps, and python3 (stdlib only).

## The playbook

Work through these in order; each step either fixes it or tells you where to look next.

1. **`./ff-crash-summary.sh`** — any recent crash dumps? `RemoteType: extension` + `MOZ_CRASH(OOM)` means the shared extension process is dying, which blanks *all* extension icons and sidebars at once. The URL annotation names an extension page in that process but is not proof of guilt — every extension lives in the same process.
2. **`./ff-mem-watch.sh`** — is the main process pegged (~100% of one core) with RSS climbing hundreds of MB per minute? That's a runaway loop, not ordinary bloat.
3. **Safe-mode baseline**: `firefox -P VERTEX -safe-mode`. If memory/CPU settle (a ~2,000-tab session idles around 3 GB), an extension is guilty; quit cleanly and continue. If it's still sick with extensions off, the problem is the profile or the binary instead — stop here and investigate those.
4. **`./ff-list-extensions.sh`** — suspects list. Extension updates are staged while the browser runs and activate at the next restart, so "it broke after I restarted" often really means "an extension updated days ago and just now activated". Recently-updated + active = prime suspect.
5. **`./ff-profiler-capture.sh -d 90`** — the decisive step. Relaunches with the Gecko profiler armed, captures the storm, dumps mid-flight via SIGUSR2, prints the profile path.
6. **`./ff-analyze-profile.py <profile.json>`** — names the culprit: hottest parent-main-thread JS frames (the *what*, e.g. `tabs.query` serialization) and `api_call` marker counts per extension (the *who*). Interpret counts against the tab count: per-tab APIs (`tabs.sendMessage`, `pageAction.setIcon`) hitting once per tab at startup is a benign sweep; a global API like `tabs.query` called hundreds of times when one call suffices is a loop. One-shot sweeps don't recur in a second capture; loops do. Load the JSON into <https://profiler.firefox.com> for the full interactive view.
7. **`./ff-remove-extension.sh -x '{ext-id}'`** — the durable kill. Use this rather than about:addons when the browser is wedged: a frozen browser can fail to persist the disable to `addonStartup.json.lz4`, so the extension silently keeps loading every restart. This moves the XPI out of the profile and clears that startup cache. (Editing `extensions.json` by hand does *not* work — Firefox ignores/overwrites it.)

Live page/session debugging by an agent: **`./ff-remote-debug.sh on|off|status`** relaunches the profile with Marionette (:2828) + WebDriver BiDi (:9222) so the `firefox-devtools` MCP (`--connect-existing`) can attach — DOM, console, network, JS eval, logpoints, Gecko profiler. Turn it `off` afterwards: remote mode sets `navigator.webdriver=true` in every tab. Procedure is in the `firefox-live-debug` Claude skill.

Auxiliary: **`./ff-session-stats.py`** prints window/tab counts and the heaviest tabs from `sessionstore.jsonlz4` (pure-Python LZ4, no packages needed). Useful for judging whether the session is big enough to make O(all-tabs) extension APIs pathological, and for verifying the session file before/after surgery.

## Hard-won gotchas

- **Nix wrapper vs pgrep**: `firefox` here is a Nix wrapper, and `pgrep -f "firefox -P VERTEX"` happily matches the launching bash, your own monitoring command, or content processes. Worse, a shell loop whose *own command line* contains the pattern deadlocks waiting for itself. `ff-lib.sh::ff_main_pid` picks the real parent (matches `bin/firefox`, excludes `-contentproc`, takes the largest RSS).
- **`kill -34` (about:memory dump) can kill Firefox** if sent before the signal handler is installed during early startup. The profiler SIGUSR2 path in `ff-profiler-capture.sh` is safer and more useful anyway.
- **SIGUSR2 needs `MOZ_UPLOAD_DIR`** or the dump silently goes nowhere. `MOZ_PROFILER_SHUTDOWN` (write on clean exit) proved unreliable when the browser was mid-meltdown.
- **The `Sandbox: CanCreateUserNamespace() EPERM` journal line is benign** on this machine — it has appeared on every launch for weeks, including healthy ones. Don't chase it.
- **One extension process**: all extensions share a single `RemoteType: extension` process. One leaker OOMs it and takes every extension down with it — which is why the symptom looks like "all extensions broke at once".
- **Session files**: back up `sessionstore.jsonlz4` + `sessionstore-backups/` before any surgery; a running browser's live session is in `sessionstore-backups/recovery.jsonlz4`.
