---
name: ai-screen-recording
description: Record demo videos and GIFs of a desktop Electron app without a human at the screen, using Playwright's built-in video recording, a drawn-in mouse pointer, coloured Before/After pills, and ffmpeg for the GIF conversion. Use for before/after GIFs for GitHub issues and PRs, or scripted regression demos of UI bugs inside an app window.
compatibility: "Requires a project that already uses Playwright (_electron API), a built app, ffmpeg, and a display (works on KDE Wayland via XWayland)"

---

How an AI agent records demo videos and GIFs of a desktop app without a human at the screen. It uses Playwright's built-in video recording, a drawn-in mouse pointer and coloured "Before"/"After" pills, then `ffmpeg` to turn the video into a GIF ready for a GitHub issue or PR.

First used to record the before/after GIFs for MarkText issue [#5631](https://github.com/marktext/marktext/issues/5631) and PR [#5632](https://github.com/marktext/marktext/pull/5632) (sidebar folders collapsing after a view switch, recorded once on `develop` and once with the fix).

## When to use this

| Approach | Cursor | Setup | Repeatable | Good for |
|----------|--------|-------|------------|----------|
| **Playwright video** (this skill) | Drawn in by the script | None if the project already uses Playwright | Yes, fully scripted | Before/after GIFs for issues and PRs, regression demos |
| OBS, recorded by hand | Real | OBS scene and screen-share approval | No | Recordings that should look natural; also counts as a manual test |
| OBS driven over obs-websocket + `ydotool` | Real | WebSocket server, a `ydotool` install, screen-coordinate mapping | Yes | Not worth the setup (see Alternatives) |

Playwright video records the **page content only**: no window frame, no desktop, and no real mouse pointer. For UI bugs inside an app window, that's usually exactly what you want.

A scripted recording is **not** a manual test. Upstream projects like MarkText expect the contributor to have tried the change themselves, so still click through it by hand before ticking "Manually tested".

## Requirements

- **Playwright** in the project. MarkText already has `@playwright/test` for its e2e tests, so its `_electron` API and `test/e2e/helpers.ts` (`getElectronPath()`) are available.
- **A built app.** For electron-vite projects that's `pnpm run build:unpack`, which writes `out/`. Playwright launches whatever is in `out/`, so rebuild after every source change.
- **`ffmpeg`.** Installed via Nix at `~/.nix-profile/bin/ffmpeg` (for the GIF conversion). Playwright also needs **its own ffmpeg build** to record video, stored in `~/.cache/ms-playwright/ffmpeg-<rev>`. Each Playwright version expects a specific revision, so after the project upgrades Playwright, run `npx playwright install ffmpeg` from the package that has Playwright installed.
- **A display.** This works on the KDE Wayland session with `DISPLAY=:0` (Electron runs under XWayland), and the window opens briefly on screen while it records. Playwright headless mode doesn't apply to Electron.

Python's `PIL` is **not** installed. To read pixel values, use `ffmpeg … -f rawvideo -pix_fmt rgb24 - | od` instead (see Converting to GIF).

## How it works

Pass `recordVideo` to `_electron.launch()`. Every window then records to a `.webm` file:

```ts
const app = await _electron.launch({
  executablePath: getElectronPath(),
  args: [projectRoot, '--user-data-dir', userData, demoFolder],
  cwd: projectRoot,
  recordVideo: { dir: videoDir, size: { width: 1100, height: 680 } },
})
```

Key points:

- **Set the window size to match the video size.** Use `BrowserWindow.setContentSize(w, h)` via `app.evaluate()`. Otherwise Playwright scales the picture down to fit 800×800.
- **Use a throwaway `--user-data-dir`.** That gives you default preferences, no session restore, and none of your own recent files.
- **The video is only written when the app closes.** Grab `page.video()` first, then `await app.close()`, then `await video.saveAs(out)`.
- **Run it as a Playwright test** with `npx playwright test <spec>` from the package that holds `playwright.config.ts`. Name the spec something obviously temporary (e.g. `zz-record-demo.spec.ts`), and delete it afterwards rather than committing it.
- **Control it with environment variables.** `DEMO_LABEL` sets the pill text and `DEMO_OUT` the output path, so the same spec records both "before" and "after".
- **Leave pauses between steps** (about 0.8 to 2.5 s) so a viewer can follow. Hold the final state longest, since that's the point of the demo.

## The fake cursor

Playwright's mouse events go straight into the page; the real pointer never moves, and the video shows no pointer at all. To fix that, inject a DOM element that follows `mousemove`, then move the mouse in steps so it glides to each target:

```ts
await page.evaluate(() => {
  const cursor = document.createElement('div')
  cursor.innerHTML =
    '<svg width="22" height="22" viewBox="0 0 24 24"><path d="M3 2l7 19 2.5-7.5L20 11z" fill="#fff" stroke="#000" stroke-width="1.5" stroke-linejoin="round"/></svg>'
  Object.assign(cursor.style, {
    position: 'fixed', left: '0', top: '0', zIndex: '2147483647',
    pointerEvents: 'none', transform: 'translate(-3px,-2px)'
  })
  document.body.appendChild(cursor)
  window.addEventListener('mousemove', (e) => {
    cursor.style.left = `${e.clientX}px`
    cursor.style.top = `${e.clientY}px`
  }, true)
  // Shrink slightly while the button is down so clicks are visible.
  window.addEventListener('mousedown', () => { cursor.style.transform = 'translate(-3px,-2px) scale(0.85)' }, true)
  window.addEventListener('mouseup', () => { cursor.style.transform = 'translate(-3px,-2px)' }, true)
})
```

```ts
const glideClick = async (locator, after = 900) => {
  const box = await locator.boundingBox()
  await page.mouse.move(box.x + Math.min(40, box.width / 2), box.y + box.height / 2, { steps: 30 })
  await pause(250)
  await page.mouse.down(); await pause(90); await page.mouse.up()
  await pause(after)
}
```

- **Use `pointerEvents: 'none'`** so the overlay never takes the clicks.
- **Use a capture-phase listener (`true`)** so the app can't stop the event before the cursor sees it.
- **Aim slightly into the target,** e.g. 40 px in from the left edge for a tree row, rather than the middle of a wide row, so the pointer lands on the text.
- **Use `steps: 30`** to give a smooth glide at about 25 fps.

## Before/After pills

A small coloured label in the bottom-right corner, so each GIF says what it shows even out of context:

| Label | Colour | Hex |
|-------|--------|-----|
| `Before: develop` | Red | `#c0392b` |
| `After: with fix` | Green | `#27ae60` |

```ts
await page.evaluate((label) => {
  const tag = document.createElement('div')
  tag.textContent = label
  Object.assign(tag.style, {
    position: 'fixed', right: '16px', bottom: '16px', zIndex: '2147483646',
    pointerEvents: 'none', padding: '6px 12px', borderRadius: '6px',
    font: '600 15px system-ui, sans-serif', color: '#fff',
    background: label.startsWith('Before') ? '#c0392b' : '#27ae60'
  })
  document.body.appendChild(tag)
}, process.env.DEMO_LABEL)
```

- **The colour comes from the label text,** so one spec serves both recordings: `DEMO_LABEL="Before: develop"` or `DEMO_LABEL="After: with fix"`.
- **The z-index is one below the cursor's,** so the pointer passes over the pill.
- **Keep it in a corner the demo doesn't use.** In MarkText the bottom-right is empty editor space.
- **Inject it after any pre-roll steps** (see Keeping private info out), so the pill appears exactly where the kept part of the video begins.

## Keeping private info out

Check the first frames for anything personal. In MarkText, the welcome page's **Recent** list showed a full local path, including the username. Two fixes worked together:

1. **A pre-roll step.** Before the demo, open a harmless file (`readme.md`) so the welcome page goes away.
2. **Trimming.** Record when the demo really starts, then cut everything before it.

The video starts when the window is created, which the script can't observe directly. So it records the seconds from the demo start to the end, and works out the offset afterwards:

```ts
const demoStart = Date.now()
// … demo steps …
fs.writeFileSync(`${OUT}.tail`, String((Date.now() - demoStart) / 1000))
```

```bash
D=$(ffprobe -v error -show_entries format=duration -of csv=p=0 after.webm)
S=$(python3 -c "print(round($D - $(cat after.webm.tail) + 0.2, 2))")   # +0.2 s so the pill has rendered
```

Also build the demo project in a `mkdtemp` folder with neutral names (`my-notes/projects/…`). The window title and breadcrumb then show something like `tmp > demo-XXXX > my-notes`, not your home directory.

## Recording before and after builds

For a bug fix, record the same script against two builds. Here, "before" means the upstream versions of the changed files:

```bash
F="path/to/changed1.vue path/to/changed2.ts"
test "$(git branch --show-current)" = fix/my-branch || { echo WRONG BRANCH; exit 1; }
trap 'git checkout HEAD -- $F; git status --short' EXIT   # always restore, even on failure
git checkout upstream/develop -- $F
pnpm run build:unpack
DEMO_LABEL="Before: develop" DEMO_OUT=/tmp/gifs/before.webm npx playwright test test/e2e/zz-record-demo.spec.ts
```

Then, on the fix branch with a fresh build, record again with `DEMO_LABEL="After: with fix"`.

- **Check the branch first.** The first "after" clip in the MarkText session was recorded on the wrong branch (`fork` instead of the PR branch). It showed fork-only features and had to be thrown away.
- **Use a `trap` to restore the files.** If the command is interrupted halfway, the swapped files would otherwise be left staged.
- **Rebuild after every swap or branch switch.** `out/` is git-ignored and silently keeps the last build.

## Converting to GIF

```bash
ffmpeg -v error -y -ss "$S" -i after.webm -filter_complex "\
crop=1100:656:0:0,fps=12,scale=880:-1:flags=lanczos,split[a][b];\
[a]palettegen=max_colors=128:stats_mode=diff[p];\
[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
-loop 0 after.gif
```

- **`crop`** removes a grey strip at the bottom. Playwright's frame was about 24 px taller than the window content. Find the edge by sampling a pixel column:
  ```bash
  for y in 652 656 657 660; do printf "$y: "; ffmpeg -v error -i frame.png -vf "crop=1:1:600:$y" -f rawvideo -pix_fmt rgb24 - | od -An -tu1; done
  ```
- **`fps=12` and `scale=880`** are plenty for UI demos, and 880 px fits GitHub's comment width.
- **`palettegen`/`paletteuse`** with `stats_mode=diff` and `diff_mode=rectangle` keep a mostly static UI small. Each 12-second clip came to about 0.5 MB.

## Checking the result

Don't post without looking. Pull a few frames out and view them (agents can read PNGs directly):

```bash
ffmpeg -v error -y -ss 6 -i after.webm -frames:v 1 check.png                  # any moment
ffmpeg -v error -y -sseof -0.3 -i before.gif -frames:v 1 b.png                # last frame of each GIF
ffmpeg -v error -y -sseof -0.3 -i after.gif  -frames:v 1 a.png
ffmpeg -v error -y -i b.png -i a.png -filter_complex hstack both.png          # side by side
```

Check that:

- the first frame shows no personal data;
- the pill and the cursor are both visible;
- the final frames clearly show the bug (before) and the fix (after).

## Posting to GitHub

**GitHub's API, and `gh`, can't upload image attachments.** So the workflow is:

1. The agent creates the issue or PR with `gh` and leaves a placeholder (`_(GIF to be added)_`, or an HTML comment).
2. You edit it in the browser and drag the GIF in. GitHub turns it into a `user-attachments` `<img>` tag.
3. The agent can confirm it worked: `gh issue view N --json body` and look for `user-attachments`.

The alternative is to push the GIFs to an assets branch on your fork and embed them by raw URL. It's fully automatic but leaves an extra branch on a public repo.

Copy the GIFs out of `/tmp` if you won't post them straight away.

## Gotchas

| Problem | Cause | Fix |
|---------|-------|-----|
| No pointer in the video | Playwright records the page only | Fake cursor |
| Video file missing or empty | Saved before the app closed | `video = page.video()`, then `app.close()`, then `video.saveAs()` |
| Grey strip along the bottom | Video frame taller than the window content | `crop` in ffmpeg |
| Picture scaled down or blurry | Video size not set | Set `recordVideo.size` and `setContentSize` to the same values |
| Local paths visible | Welcome page, recent files, title bar | Pre-roll, trimming, throwaway user-data dir, neutral temp folder |
| Wrong features in the clip | Recorded on the wrong branch or a stale `out/` | Check the branch and rebuild before each recording |
| Swapped files left staged | Interrupted halfway | Restore them with a `trap` |
| Opening a folder attaches to a second window | MarkText starts a new window for a directory argument | Poll `app.windows()` for the one showing the sidebar |
| `_electron.launch()` hangs until the test times out, but only with `recordVideo` set | Playwright's own ffmpeg is missing for the installed Playwright version (e.g. after a dependency upgrade bumped it to 1.64) | Run `npx playwright install ffmpeg`, then check that `~/.cache/ms-playwright/ffmpeg-*` exists |
| Launch fails with `TypeError: Invalid URL` | `pnpm run dev` overwrote `out/` with a dev build that expects the Vite dev server | Rebuild with `pnpm run build:unpack` |
| The folder never opens in the sidebar | A hand-written minimal `preferences.json` in the throwaway `--user-data-dir` | Don't seed preferences, or use the project's own helper (MarkText's `launchElectron({ preferences })`) |

## Full script template

This is the spec used for MarkText (Electron + Playwright). Put it in the e2e folder so it can import `helpers.ts`, run it, and then delete it.

```ts
// Throwaway: records a demo video. Not for committing.
import { test, expect } from '@playwright/test'
import { _electron, type Page } from 'playwright'
import * as fs from 'node:fs'
import * as os from 'node:os'
import * as path from 'node:path'
import { getElectronPath } from './helpers'

const LABEL = process.env.DEMO_LABEL ?? 'demo'
const OUT = process.env.DEMO_OUT ?? '/tmp/demo.webm'
const W = 1100
const H = 680
const pause = (ms: number) => new Promise((r) => setTimeout(r, ms))

test.setTimeout(120000)

test('record demo', async () => {
  const projectRoot = path.resolve(__dirname, '../..')

  // Neutral demo content in a temp folder.
  const projectDir = fs.mkdtempSync(path.join(os.tmpdir(), 'demo-'))
  const root = path.join(projectDir, 'my-notes')
  fs.mkdirSync(path.join(root, 'projects', 'marktext'), { recursive: true })
  fs.mkdirSync(path.join(root, 'journal'), { recursive: true })
  fs.writeFileSync(path.join(root, 'readme.md'), '# Readme\n')
  fs.writeFileSync(path.join(root, 'journal', '2026-10-05.md'), '# Journal\n')
  fs.writeFileSync(path.join(root, 'projects', 'ideas.md'), '# Ideas\n')
  fs.writeFileSync(path.join(root, 'projects', 'marktext', 'notes.md'),
    '# Notes\n\n## Sidebar\n\nSome text.\n\n## Folder state\n\nMore text.\n\n## Next steps\n\nEven more.\n')
  const userData = fs.mkdtempSync(path.join(os.tmpdir(), 'demo-ud-'))
  const videoDir = fs.mkdtempSync(path.join(os.tmpdir(), 'demo-video-'))

  const app = await _electron.launch({
    executablePath: getElectronPath(),
    args: [projectRoot, '--user-data-dir', userData, root],
    cwd: projectRoot,
    recordVideo: { dir: videoDir, size: { width: W, height: H } },
    timeout: 30000
  })

  // Opening a directory can attach to a window other than the first one.
  let page: Page | undefined
  await expect.poll(async () => {
    for (const w of app.windows()) {
      if (await w.locator('.side-bar-file').count()) { page = w; return true }
    }
    return false
  }, { timeout: 15000 }).toBe(true)
  const p = page!

  await app.evaluate(({ BrowserWindow }, s) => {
    for (const win of BrowserWindow.getAllWindows()) { win.setContentSize(s.w, s.h); win.center() }
  }, { w: W, h: H })
  await pause(600)

  // Pre-roll: get past the welcome page (Recent list shows local paths).
  await p.locator('.side-bar-file[title$="readme.md"]').click()
  await pause(1000)
  const demoStart = Date.now()

  // Overlays: fake cursor and before/after pill (see the sections above).
  await p.evaluate((label) => {
    /* cursor + pill code from the sections above */
  }, LABEL)

  await p.mouse.move(W * 0.6, H * 0.5)
  await pause(800)

  const glideClick = async (locator: ReturnType<Page['locator']>, after = 900) => {
    const box = await locator.boundingBox()
    if (!box) throw new Error('target not visible')
    await p.mouse.move(box.x + Math.min(40, box.width / 2), box.y + box.height / 2, { steps: 30 })
    await pause(250)
    await p.mouse.down(); await pause(90); await p.mouse.up()
    await pause(after)
  }
  const folder = (name: string) => p.locator('.side-bar-folder > .folder-name', { hasText: name }).first()
  const icon = (i: number) => p.locator('.side-bar .left-column > ul').first().locator('li').nth(i)

  // The demo itself.
  await glideClick(folder('projects'))
  await glideClick(folder('marktext'))
  await glideClick(p.locator('.side-bar-file[title$="notes.md"]'), 1200)
  await glideClick(icon(2), 1800) // Table of Contents
  await glideClick(icon(0), 2500) // back to Files: hold the result

  // Seconds from demo start to end; trim offset = video duration minus this.
  fs.writeFileSync(`${OUT}.tail`, String((Date.now() - demoStart) / 1000))
  const video = p.video()
  await app.close()
  await video!.saveAs(OUT)
  for (const d of [projectDir, userData, videoDir]) fs.rmSync(d, { recursive: true, force: true })
})
```

Run it:

```bash
mkdir -p /tmp/gifs
cd packages/desktop
DEMO_LABEL="After: with fix" DEMO_OUT=/tmp/gifs/after.webm npx playwright test test/e2e/zz-record-demo.spec.ts
```

Then trim and convert as in Keeping private info out and Converting to GIF.

## Alternatives considered

**OBS driven over its WebSocket API.** OBS 28+ includes obs-websocket, so an agent can switch scenes and start/stop recording from a script with no MCP server. The setup costs:

- the WebSocket server has to be enabled in OBS (Tools → WebSocket Server Settings);
- on Wayland, screen capture needs a one-off screen-sharing approval in the portal dialog, which only a human can click;
- Playwright's clicks still don't move the real pointer.

A real moving cursor would need `ydotool` (not installed; it needs a Nix package and `/dev/uinput` access), plus mapping app coordinates to screen coordinates under Wayland scaling. That's too much setup for a couple of GIFs. It's only worth doing if a real cursor or the window frame matters.

**Recording by hand in OBS.** This gives the most natural result, and doubles as the manual test upstream projects expect. Prefer it when a human is around anyway.
