---
name: firefox-extension-development
description: >-
  Develop, build, sign, and test Firefox WebExtensions on this machine — from first scaffold through signing a self-distributed XPI on AMO and installing it in the VERTEX profile. Use whenever the user is working on a Firefox extension, add-on, .xpi, manifest.json / web-ext workflow, about:debugging temporary add-ons, AMO signing, or a repo that builds browser extensions (e.g. Logseq Copilot). Also use when the user says things like "rebuild the extension", "sign the xpi", "reload my add-on", or "extension data reset" for Firefox.
compatibility: "Requires pnpm + web-ext for signing; AMO API creds for the signing step"
---

# Firefox extension development

The canonical notes for this workflow live in Logseq block `69dd1438-f29b-4663-a474-49bfa080f6bc` (graph `logseq-apex`, under `Browser extensions → Documentation → [[Firefox]]-specific`). To pull the latest version at any time, use the `logseq-cli` skill:

```
logseq show --graph logseq-apex --id 500710 --level 5
```

The steps below are a distilled copy of that block — prefer the block when output or commands seem to have drifted.

## 1. Building

Output of a build: unpacked add-on in `build/firefox/` plus `build/firefox-<version>.zip`.

- **Bump the version every time you plan to sign** — AMO refuses to sign a version it has already signed for a given add-on ID. Without `VERSION`, the build defaults to `0.0.0`.
- Two equivalent ways to build:
  - `VERSION=0.0.1 node build.mjs` — skips pnpm's dependency check, works even when pnpm wants to reinstall `node_modules`.
  - `VERSION=0.0.1 pnpm run build` — **run inside the repo's dev shell** (`nix develop`, or direnv). The dev shell provides pnpm 10; the home-profile pnpm 11 fails with `Command failed with exit code 1: pnpm install` because it wants to reinstall `node_modules`. Don't "fix" that by running `pnpm install` with pnpm 11 — use the dev shell or `node build.mjs` instead.

## 2. Signing (self-distribution, unlisted)

Needs AMO API credentials from https://addons.mozilla.org/developers/addon/api/key/ — export them first:

```
export WEB_EXT_API_KEY=...
export WEB_EXT_API_SECRET=...
pnpm run publish:firefox
```

`publish:firefox` runs `web-ext sign -s build/firefox`, which uploads the build to AMO, signs it as an **unlisted** add-on, and downloads the signed XPI back to `web-ext-artifacts/<hash>-<version>.xpi`.

**Without a repo build script** (a bare add-on folder, e.g. `firefox-live-debug/tab-closer/`): give the user this to run themselves — it prompts for the key/secret without echoing them or saving them to shell history. Don't ask the user to paste the credentials into the chat.

```bash
cd <dir containing the add-on folder>
read -rp 'AMO key: ' WEB_EXT_API_KEY; read -rsp 'AMO secret: ' WEB_EXT_API_SECRET; echo
WEB_EXT_API_KEY=$WEB_EXT_API_KEY WEB_EXT_API_SECRET=$WEB_EXT_API_SECRET \
  web-ext sign --channel unlisted -s <addon-folder> \
  [--ignore-files <non-addon files, e.g. host.py>] --artifacts-dir /tmp/<addon>-signed
```

Before handing it over, run `web-ext lint -s <addon-folder>` yourself (same `--ignore-files`). New add-ons need `browser_specific_settings.gecko.data_collection_permissions` (e.g. `{"required": ["none"]}`) in `manifest.json` or AMO rejects them, and a fixed `gecko.id` so later versions update in place. Signing takes a few minutes; the signed XPI lands in the `--artifacts-dir`.

## 3. Installing the signed XPI (profile: VERTEX)

Option A (recommended — no restart):
`about:addons` → gear icon → **Install Add-on From File…** → pick `web-ext-artifacts/<hash>-<version>.xpi`. Replaces the installed copy (same ID, newer version) in place.

Option B (needs a restart):

```
cp web-ext-artifacts/*-0.0.1.xpi \
   "$HOME/.mozilla/firefox/VERTEX/extensions/{b460bedc-e57a-47bd-9561-f3f1b226fadd}.xpi"
```

Match the version in the filename — `web-ext-artifacts/` keeps older signed XPIs and a bare `*.xpi` glob to a single destination fails once there's more than one. Only takes effect after a Firefox restart.

Verify afterwards in `about:addons` that the extension shows the new version.

## 4. Testing without signing

- **Dev loop:** `about:debugging` → "This Firefox" → "Load Temporary Add-on" → pick any file inside `build/firefox/` (e.g. `manifest.json`). Zero friction — rebuild with `pnpm run build` and hit **Reload**; no restart needed, works in release Firefox. The extension disappears on restart.
- **Persistent unsigned install:** Firefox Developer Edition has `xpinstall.signatures.required = false` by default, so unsigned .xpi files can be installed permanently via `about:addons` → gear → "Install Add-on From File". DevEdition runs alongside regular Firefox.

## 5. Testing on Android (`web-ext run` + adb)

`web-ext run --target=firefox-android` pushes the extension to a phone over adb and installs it as a **temporary add-on in the app's main profile** (not a throwaway profile). It live-reloads on source changes while the watcher runs — keep the command running in the background for the whole test session (a `timeout` kills the watcher and the add-on disappears on the next app restart).

Phone prerequisites:

- USB debugging enabled; `adb devices` on the host shows the device id.
- In the Firefox app: **Settings → Developer Tools → "Remote Debugging via USB"**. If Developer Tools is missing, unlock it via Settings → About → tap the Firefox logo ~5×.
- At least one tab open in the app — web-ext can't load the extension otherwise.

Run it:

```
adb devices                                   # get <device-id>
adb shell pm list packages | grep -i mozilla  # list installed Firefox APK ids
web-ext run -s <source-dir> --target=firefox-android \
  --android-device=<device-id> --firefox-apk=<package>
```

Which `--firefox-apk` to use:

- `org.mozilla.firefox_beta` — Beta. Accepts debug installs, matches release behavior most closely. Good default.
- `org.mozilla.fenix` — Nightly. Same debug support, and (with Beta) the only channel with the custom add-on collection menu (persistent install of any AMO-listed extension). More churn, updates ~daily.
- `org.mozilla.fennec_fdroid` — Fennec F-Droid, also debuggable.
- `org.mozilla.firefox` — release. Locked to the curated extension list; debug installs effectively don't work.

Notes:

- The temp add-on is removed when the debug session ends or the app restarts — expected.
- web-ext logs `You can connect to this Android device on TCP port XXXXX` — the device then shows up in desktop `about:debugging` for inspecting the extension's pages/console while it runs.
- `Old artifacts directories have been found` warning → rerun with `--adb-remove-old-artifacts`.
- Touch/pointer-event bugs usually also reproduce on desktop without a device: F12 → Responsive Design Mode (Ctrl+Shift+M) → enable touch simulation. Much faster loop; reach for the phone only for confirmation.

### Persistent install on Android (signed XPI required)

Fenix has an **"Install add-on from file"** preference (`pref_key_install_local_addon` in `SettingsFragment.kt`) that does a real persistent install via `AddonManager.installAddon(uri, InstallationMethod.FROM_FILE)`. Its only gate is `showSecretDebugMenuThisSession` — **not** the release channel — so it works on Fennec F-Droid and Beta, not just Nightly (verified against firefox-main source; the fennecbuild patches don't touch this path). Unlisted/self-signed XPIs work since signature checking is all that applies.

Steps:

1. Push the signed XPI: `adb push web-ext-artifacts/<hash>-<version>.xpi /sdcard/Download/` (or copy it over any way — the picker accepts `application/x-xpinstall` and `application/zip`).
2. In the app: **Settings → About** → tap the logo ~5× to enable the debug menu for this session.
3. **Settings → Extensions → "Install add-on from file"** → pick the XPI → confirm.

Caveats:

- The debug menu unlock is per-session; if the menu item vanishes after a restart, tap the logo again. The **installed add-on persists regardless**.
- No auto-updates: bump `version`, re-sign, re-install from file (same `gecko.id` updates in place).
- A different `gecko.id` than the AMO-listed original installs as a separate extension with default settings.
- **Custom Add-on Collection** (the other persistent path, installs straight from AMO) IS channel-gated: `FeatureFlags.customExtensionCollectionFeature = isNightlyOrDebug || isBeta`, so Nightly/Beta only — not Fennec release.
- Rooted alternative: drop the XPI into `/data/data/<pkg>/files/mozilla/<profile>.default/extensions/<gecko.id>.xpi`.

## 6. Resetting extension data

- Open the extension's background page console: `about:debugging#/runtime/this-firefox` → pick the extension → **Inspect**.
- Or remove the extension entirely and reload the browser.

## Related

- For driving/debugging the live Firefox session (console, network, DOM of a running tab): use the `firefox-live-debug` skill — the firefox-devtools MCP only attaches once Firefox is restarted with Marionette + BiDi.
- For just driving a site in a browser, prefer `chromium-live-debug` / `chromium-devtools-isolated`.
