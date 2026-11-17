---
name: android-linux-terminal-automation
description: >-
  Drive the Android "Linux Terminal" app (AVF/crosvm Debian VM) on the Pixel 8 from this machine: run commands in the VM, read its output, and enrol it on the Headscale tailnet. Use when the user mentions the Pixel VM, the Linux Terminal app on the phone, the "Glider" scrcpy window, or wants something done inside that Debian VM.
---

# Android Linux Terminal (AVF VM) automation

The Pixel 8 runs a Debian VM (AVF/crosvm) behind the `com.android.virtualization.terminal` app. Its shell has **no programmatic exec channel** — `vm console` and `vm start-adbd` (`/apex/com.android.virt/bin/vm`) only work for VMs launched via the `vm` tool, and the Terminal app itself is the only UI into the guest.

The working channel is:

- **Input**: `adb shell input -d <logical-display> text ...` — types into the terminal's surface on the scrcpy virtual display.
- **Output**: `adb exec-out screencap -p -d <surfaceflinger-id>` → `tesseract` OCR. The terminal canvas is not accessibility-readable (only the tab title appears in `uiautomator dump`).

All of this is wrapped by **`scripts/pixel-vm.sh`** (in this skill's directory) — prefer it over hand-rolling adb calls.

## Wrapper script (preferred)

```bash
cd ~/Projects/installs
./scripts/pixel-vm.sh status          # OCR'd `tailscale status` from inside the VM
./scripts/pixel-vm.sh join            # join the Headscale tailnet (mints a pre-auth key via `ssh don@headscale`)
./scripts/pixel-vm.sh send 'ls -la'   # type + Enter into the VM shell
./scripts/pixel-vm.sh ocr             # OCR the current terminal screen
./scripts/pixel-vm.sh screenshot [p]  # PNG of the VM display (default /tmp/pixel-vm-screen.png)
```

Env overrides: `ADB_SERIAL`, `VM_HOSTNAME` (default `pixel-vm`), `HS_SSH` (default `don@headscale`), `LOGIN_SERVER` (default `https://15-hs.example.com`).

Requires: phone on USB/wireless adb, **tesseract** installed locally, and a scrcpy window currently presenting the Terminal app (the virtual display only exists while a client like scrcpy shows it).

## Which scrcpy window/display is the terminal — do not rely on the window title

The scrcpy window title ("Glider", "Pixel 8", whatever) is set by the user and is unreliable. Identify the display **on the device**, by which package owns the activity:

```bash
# 1) logical input displayId of the Terminal app's focused window
adb shell 'dumpsys input | grep "virtualization.terminal/.new2" | grep -o "displayId=[0-9]*" | head -1'
# → e.g. displayId=23

# 2) its viewport uniqueId (contains "scrcpy" if scrcpy owns the display)
adb shell "dumpsys input | grep 'displayId=23, uniqueId'"
# → displayId=23, uniqueId='virtual:com.android.shell,2000,scrcpy,21', ...

# 3) map uniqueId → SurfaceFlinger id for screencap
adb shell 'dumpsys SurfaceFlinger --display-id' | grep "scrcpy,21"
# → Display 11529215049472961368 (Virtual display): ... uniqueId="virtual:...,scrcpy,21"
```

Then: `input -d 23` sends keys/taps there; `screencap -d 11529215049472961368` grabs its pixels.

Fallback / sanity checks:

- `adb shell /apex/com.android.virt/bin/vm list` — the VM must be running (`name: "debian"`, note the `cid`).
- `adb shell 'dumpsys activity activities | grep virtualization.terminal'` — task exists.
- If the uniqueId contains something other than `scrcpy` (e.g. another virtual-display client), it still works — the ids are what matter, not who owns the display.
- If no `virtualization.terminal` window is on any display, the Terminal app isn't open; ask the user to open it — `am start -n com.android.virtualization.terminal/.new2.ui.MainActivity` is Permission Denied (activity not exported) and there is no workaround from adb.

## Doing it by hand (what the script does)

```bash
adb shell input -d 23 tap 900 500          # focus the terminal surface (inside display bounds, below the tab bar)
adb shell input -d 23 text 'whoami'        # spaces must be escaped: 'ls\ -la'
adb shell input -d 23 keyevent 66          # Enter
sleep 2
adb exec-out screencap -p -d 11529215049472961368 > /tmp/vm.png
tesseract /tmp/vm.png -
```

## Tailscale enrolment (Headscale tailnet)

The tailnet is self-hosted Headscale at `https://15-hs.example.com` (nodes get `<name>.device.example.com`). `./scripts/pixel-vm.sh join` does:

1. `ssh don@headscale 'sudo docker exec headscale headscale preauthkeys create --user 1 --reusable --expiration 24h'` → `hskey-auth-…`
2. In the VM: `sudo tailscale up --login-server https://15-hs.example.com --auth-key <key> --hostname pixel-vm` (`droid` has passwordless sudo).
3. Verifies with `tailscale ip -4`.

First successful join gave **pixel-vm = 100.x.x.x**. If key minting fails, `join` falls back to interactive `tailscale up` and OCRs the screen — open the login URL yourself and approve the node. `join` is idempotent (re-running on an enrolled VM is a no-op for tailscaled state; it just re-auths the key).

## Sending files to the VM — use taildrop, not the terminal

Once the VM is on the tailnet, files go over taildrop. This is the only reliable file channel — `input`/OCR cannot carry file contents, and there is no shared `/sdcard` with Android.

```bash
# 1) push file(s) into the VM's taildrop inbox (no confirmation output on success)
tailscale file cp file1.apk file2.apk pixel-vm:
#    pixel-vm resolves by name or by 100.x.x.x

# 2) inside the VM (via pixel-vm.sh send, then verify with ocr):
#    the inbox dir /var/lib/tailscale/files is root-only — `ls` as droid
#    gives Permission denied. `tailscale file get` moves them out:
./scripts/pixel-vm.sh send 'sudo tailscale file get ~/iplayer'
./scripts/pixel-vm.sh send 'ls -l ~/iplayer'
./scripts/pixel-vm.sh ocr      # confirm the files landed
```

Notes:
- `tailscale file cp <files> <node>:` — trailing `:` targets the node's inbox. Silent on success.
- `tailscale file get <dir>` requires sudo (inbox is root-owned) and moves inbox files into `<dir>`.
- Pulling files *from* the VM has no taildrop equivalent; use `scp`/http once sshd or a web server runs in the guest, or just OCR the result of `cat`.

## Gotchas

- **`input text` quirks**: escape spaces as `\ `; avoid `|`, `>`, `$()` in commands — on this build a piped command leaked into a different app (`droiddeck`) instead of the terminal. Prefer short single commands; chain on the host side instead.
- **`/sdcard` does not exist in the VM** — no shared storage with Android; file-based I/O is impossible over the terminal channel. To *send files to the VM* use taildrop, not the terminal (see below).
- **OCR is lossy** on punctuation (`£`, `1`/`l`, `0`/`O`). Verify state with commands whose output OCRs reliably (`tailscale ip -4`, `hostname`), not by eyeballing echoed commands.
- **Focus can wander**: tap inside the display before typing; if text lands in the wrong app, retap and retry. Phone display 0 (`input` without `-d`) is a different screen — never send there.
- **Remote grep is toybox** — no `-P`/`grep -oP` inside `adb shell`; use `grep -o`/`awk`. Parse locally where possible.
- **Display ids change per scrcpy session** — always re-resolve, never hardcode.
- `vm console <cid>` fails for this VM ("Failed to get VM with console") — Terminal-app VMs have no host console; don't waste time there.
