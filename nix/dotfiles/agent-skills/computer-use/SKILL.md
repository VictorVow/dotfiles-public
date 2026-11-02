---
name: computer-use
description: >-
  Decide how to drive a GUI on this machine (KDE Plasma 6, Wayland): routes the task to the right tool — `agent-desktop` for native-app windows (headless AT-SPI, Orca's `orca computer` as real-input fallback), the browser DevTools MCPs for web pages, or a nested KWin/VM for isolated runs — and explains which computer-use options exist on Linux, which are installed here, and which vendor skills are macOS-only betas. Read before any "click / type into / look at an app window" request.
---

# Computer use on this machine

Desktop: **Kubuntu, KDE Plasma 6.6.6, Wayland**. Wayland blocks the X11 free-for-all (any client reading any window's pixels and injecting input), so "computer use" here is a set of layered options, not one tool. Full research: `docs/research/ai-computer-use-linux.md`.

## Pick the right tool, in order

1. **A programmatic path exists → use it.** Shell, filesystem, git, HTTP, app CLIs. Always preferred over driving pixels.
2. **The target is a web page → browser MCP**, not desktop control:
   - `firefox-devtools` MCP + `firefox-live-debug` skill — the live VERTEX Firefox profile (Marionette + WebDriver BiDi).
   - `chromium-devtools` MCP + `chromium-live-debug` skill — the live Chromium/Chrome/Brave on CDP port 9223.
   - `chromium-devtools-isolated` MCP — throwaway headless Chromium, clean profile.
3. **A native app window needs GUI control → `agent-desktop` CLI** (Vercel Labs, `npm i -g agent-desktop`; on PATH). Reads any app's AT-SPI tree into stable `@snapshot:ref` handles and acts on refs headlessly — no focus stealing, no pixel guessing. Loop: `agent-desktop status` → `snapshot --app <name> -i --compact` → `click @sXXXX:eN` → snapshot again. Self-documents: `agent-desktop skills get desktop` and `agent-desktop skills get linux` (Linux/Wayland capability table and gotchas). Fall back to the `orca-computer-use` skill (`orca computer`) when an app doesn't appear on the a11y bus (Chromium/Electron need their a11y flag) or a semantic action refuses with `ACTION_NOT_SUPPORTED`/`POLICY_DENIED` — Orca can raise the window and take real input.
4. **Isolated / autonomous runs → give the agent its own display.** `kwin-mcp` virtual sessions (`dbus-run-session` + `kwin_wayland --virtual`, private EIS input, no portal dialogs) or a container/VM with Xvfb. Nothing on the real desktop, nothing at stake. Not installed yet — see "Not installed" below.

## What exists vs what's installed here

| Option | Status on this machine |
|---|---|
| `agent-desktop` (Vercel Labs, AT-SPI CLI) | **Installed** via npm-globals. Headless semantic actions work on Wayland. Gaps: no headed pointer input, `press` keys need Mutter (X11/XTEST only), window control X11-only, notifications GNOME-only, screenshots via portal consent. Docs: `agent-desktop skills get linux`. |
| `orca computer` (Orca app GUI automation) | **Installed.** Foreground input fallback for what agent-desktop can't do (real clicks/keys). Use the `orca-computer-use` skill. |
| Browser DevTools MCPs (firefox/chromium/×2) | **Installed**, wired in `nix/modules/ai-agents.nix` |
| Anthropic synced `computer-use` skill | **Disabled here.** It drives `mcp__computer-use__*` tools that only exist inside Claude Desktop on macOS/Windows — the Linux desktop beta ships no screen control, so the skill is inert on this machine. |
| OpenAI Codex app computer use | **Not available.** Its own-cursor computer use is a macOS-only beta (added Apr 2026); the Linux Codex CLI has no desktop control, only browser-level Playwright. `~/.config/codex/computer-use/` is just its UI prefs. |
| `kwin-mcp` (KDE virtual sessions + live attach) | Not installed. KDE-only, `uv`/`pip` install, would register in `ai-agents.nix` |
| `computer-use-linux` (agent-sh, Rust MCP) | Not installed. Cross-desktop backend picker (portal/ydotool/KWin scripting/AT-SPI); only manually validated on GNOME |
| Anthropic computer-use **API** tool / OpenAI GPT-5.4 CUA | Available at API level, but both are "bring your own executor" — you'd build the screenshot/input loop yourself |
| Open-source agents (Agent S3, UI-TARS, Bytebot, Cua) | Not installed. All assume X11 or their own VM/container |

## Vendor beta note

Anthropic's and OpenAI's official desktop computer-use features are **macOS-first betas** (Windows second; Linux excluded). The models themselves are OS-agnostic — both APIs just return actions like "click at (x,y)" — so Linux support is blocked on the driver layer, not the model. When either vendor ships Linux computer use (likely via the XDG RemoteDesktop portal + libei with consent dialogs), re-check whether the Anthropic synced skill becomes live here and whether disabling it is still wanted.

## Safety rules for any desktop-control task

- Read-only inspection (`snapshot`, `find`, screenshots) is fine to do unannounced; anything that clicks, types, submits, deletes, or buys needs the user's explicit ask.
- agent-desktop's default headless mode never takes focus; `orca computer` on Linux raises the window and takes real input — tell the user before that, and never pass `--headed` to agent-desktop unless the user explicitly permits physical input.
- Live-session control sees and touches everything visible — notifications, password managers, vaults. Snapshots and screenshots go to the model provider. Prefer a nested session when secrecy matters.
- Never click links inside native apps with desktop-control tools; open the URL in a browser via the browser MCPs instead.
