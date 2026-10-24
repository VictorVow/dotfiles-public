---
name: firefox-extension-development
description: >-
  Develop, build, sign, and test Firefox WebExtensions on this machine — from first
  scaffold through signing a self-distributed XPI on AMO and installing it in the
  VERTEX profile. Use whenever the user is working on a Firefox extension, add-on,
  .xpi, manifest.json / web-ext workflow, about:debugging temporary add-ons, AMO
  signing, or a repo that builds browser extensions (e.g. Logseq Copilot). Also
  use when the user says things like "rebuild the extension", "sign the xpi",
  "reload my add-on", or "extension data reset" for Firefox.
compatibility: "Requires pnpm + web-ext for signing; AMO API creds for the signing step"
---

# Firefox extension development

The canonical notes for this workflow live in Logseq block
`69dd1438-f29b-4663-a474-49bfa080f6bc` (graph `logseq-apex`, under
`Browser extensions → Documentation → [[Firefox]]-specific`). To pull the latest
version at any time, use the `logseq-cli` skill:

```
logseq show --graph logseq-apex --id 500710 --level 5
```

The steps below are a distilled copy of that block — prefer the block when output
or commands seem to have drifted.

## 1. Building

Output of a build: unpacked add-on in `build/firefox/` plus `build/firefox-<version>.zip`.

- **Bump the version every time you plan to sign** — AMO refuses to sign a version
  it has already signed for a given add-on ID. Without `VERSION`, the build
  defaults to `0.0.0`.
- Two equivalent ways to build:
  - `VERSION=0.0.1 node build.mjs` — skips pnpm's dependency check, works even when
    pnpm wants to reinstall `node_modules`.
  - `VERSION=0.0.1 pnpm run build` — **run inside the repo's dev shell**
    (`nix develop`, or direnv). The dev shell provides pnpm 10; the home-profile
    pnpm 11 fails with `Command failed with exit code 1: pnpm install` because it
    wants to reinstall `node_modules`. Don't "fix" that by running
    `pnpm install` with pnpm 11 — use the dev shell or `node build.mjs` instead.

## 2. Signing (self-distribution, unlisted)

Needs AMO API credentials from
https://addons.mozilla.org/developers/addon/api/key/ — export them first:

```
export WEB_EXT_API_KEY=...
export WEB_EXT_API_SECRET=...
pnpm run publish:firefox
```

`publish:firefox` runs `web-ext sign -s build/firefox`, which uploads the build
to AMO, signs it as an **unlisted** add-on, and downloads the signed XPI back to
`web-ext-artifacts/<hash>-<version>.xpi`.

## 3. Installing the signed XPI (profile: VERTEX)

Option A (recommended — no restart):
`about:addons` → gear icon → **Install Add-on From File…** → pick
`web-ext-artifacts/<hash>-<version>.xpi`. Replaces the installed copy (same ID,
newer version) in place.

Option B (needs a restart):

```
cp web-ext-artifacts/*-0.0.1.xpi \
   "$HOME/.mozilla/firefox/VERTEX/extensions/{b460bedc-e57a-47bd-9561-f3f1b226fadd}.xpi"
```

Match the version in the filename — `web-ext-artifacts/` keeps older signed XPIs
and a bare `*.xpi` glob to a single destination fails once there's more than one.
Only takes effect after a Firefox restart.

Verify afterwards in `about:addons` that the extension shows the new version.

## 4. Testing without signing

- **Dev loop:** `about:debugging` → "This Firefox" → "Load Temporary Add-on" →
  pick any file inside `build/firefox/` (e.g. `manifest.json`). Zero friction —
  rebuild with `pnpm run build` and hit **Reload**; no restart needed, works in
  release Firefox. The extension disappears on restart.
- **Persistent unsigned install:** Firefox Developer Edition has
  `xpinstall.signatures.required = false` by default, so unsigned .xpi files can
  be installed permanently via `about:addons` → gear → "Install Add-on From File".
  DevEdition runs alongside regular Firefox.

## 5. Resetting extension data

- Open the extension's background page console:
  `about:debugging#/runtime/this-firefox` → pick the extension → **Inspect**.
- Or remove the extension entirely and reload the browser.

## Related

- For driving/debugging the live Firefox session (console, network, DOM of a
  running tab): use the `firefox-live-debug` skill — the firefox-devtools MCP only
  attaches once Firefox is restarted with Marionette + BiDi.
- For just driving a site in a browser, prefer `chromium-live-debug` /
  `chromium-devtools-isolated`.
