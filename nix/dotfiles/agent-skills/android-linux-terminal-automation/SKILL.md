---
name: android-linux-terminal-automation
description: >-
  Drive the Android "Linux Terminal" app (AVF/crosvm Debian VM) on the Pixel 8 from this machine: run commands in the VM, read its output, bootstrap a fresh Debian install onto the tailnet + Nix/Home Manager, and enrol it on the Headscale tailnet. Use when the user mentions the Pixel VM, the Linux Terminal app on the phone, the "Glider" scrcpy window, or wants something done inside that Debian VM.
---

# Android Linux Terminal (AVF VM) automation

The Pixel 8 runs a Debian VM (AVF/crosvm) behind the `com.android.virtualization.terminal` app. adb has **no exec channel into the guest** — `vm console` and `vm start-adbd` (`/apex/com.android.virt/bin/vm`) only work for VMs launched via the `vm` tool, and the Terminal app is the only UI into it. The escape hatch is ssh: once the VM has tailscale + `tailscale set --ssh`, the tailnet gives a proper channel (that's what `vm-bootstrap.sh` sets up).

There are **two channels** into the VM — which one to use depends on whether Tailscale SSH is up:

- **ssh (preferred, post-bootstrap)**: `ssh droid@100.x.x.x` over the tailnet (Tailscale SSH on port 22 — tailnet ACL auth, no keys needed). Use for *everything* once it's up: commands, `scp`/`rsync`, long jobs, exact output. No OCR loss, no terminal drops.
- **Terminal channel (bootstrap / fallback only)**: `input -d` keystrokes + `screencap` OCR via `pixel-vm.sh`. Lossy and fragile — needed only to *install* tailscale on a fresh VM, and as a rescue path if tailscaled/sshd dies.

Rule of thumb: try ssh first; reach for `pixel-vm.sh` only when ssh can't connect or the VM isn't enrolled yet.

| Task | Channel |
|---|---|
| Anything on an enrolled, sshd-up VM | ssh (`droid@<tailnet-ip>`) |
| Files in/out | `scp`/`rsync` over ssh; taildrop only pre-sshd |
| Install tailscale on a fresh VM | terminal (`pixel-vm.sh send`) |
| `tailscale up` / enrolment | terminal (pre-tailnet by definition) |
| Long-running jobs (nix builds, GC) | ssh, or `setsid nohup … > log` — terminal sessions die under load |
| Recovering when tailscaled/sshd is dead | terminal (that's its rescue role) |
| Reading a TUI / watching a `less` | terminal + screenshot |

```bash
# ssh channel — the day-to-day one (host key file if you don't want it in ~/.ssh/known_hosts)
ssh -o UserKnownHostsFile=/tmp/opencode/vm_hosts -o BatchMode=yes droid@100.x.x.x 'free -m'
scp -o UserKnownHostsFile=/tmp/opencode/vm_hosts file.tgz droid@100.x.x.x:~/   # faster+cleaner than taildrop
```

The terminal channel, wrapped by **`scripts/pixel-vm.sh`**:

- **Input**: `adb shell input -d <logical-display> text ...` — types into the terminal's surface on the scrcpy virtual display.
- **Output**: `adb exec-out screencap -p -d <surfaceflinger-id>` → `tesseract` OCR. The terminal canvas is not accessibility-readable (only the tab title appears in `uiautomator dump`).

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

## Fresh-VM bootstrap — `scripts/vm-bootstrap.sh`

Takes a pristine Debian install (terminal-only access, no tailscale/sshd) to a tailnet node running the repo's HM config:

```bash
./scripts/vm-bootstrap.sh                     # interactive (asks before phase 6)
./scripts/vm-bootstrap.sh --run-bootstrap     # fully unattended
./scripts/vm-bootstrap.sh --skip-bootstrap    # tailnet+repo only, no nix install
```

Phases: 1) apt tailscale + `join` + `tailscale set --ssh` → real ssh channel on `100.64.0.x`; 2) swap; 3) apt `git age`; 4) `~/.config/sops/age/keys.txt` generated over ssh, pubkey printed locally; 5) repo tarball → taildrop → `~/installs` → `git init`+`git add -A` (flakes only see tracked files); 6) `./bootstrap.sh droid` detached to `~/bootstrap.log`.

After it finishes, the only manual bit is sops: put the printed pubkey in `.sops.yaml` (`&droid`), add `*droid` to the `ai-droid.yaml` rule, `sops updatekeys nix/secrets/ai-droid.yaml`, fill the real values, re-sync + `hms`. Then optionally `apt remove git age` (the nix profile owns them).

### Memory on the VM (~1 GB RAM — nix eval OOMs without swap)

Bootstrap provisions both kinds; the split is deliberate:

- **Persistent: `/swapfile` (4G default, `SWAP_GB`)** on the vda rootfs + fstab entry. This is the one that survives reboots — no module needed at boot.
- **Transient: extra zram (`ZRAM_MB`, default 2048)** via `zramctl -f` at bootstrap time. Not persisted — the device (`zram1`+) doesn't exist at boot, so an fstab line would just error. Recreate with `zramctl -f -s 2G` if a big eval OOMs after a reboot. The VM image already ships a ~240M `zram0` at prio 100.

### Storage: two traps

- `/mnt/backup` (`/dev/vdc`) is the VM's **own system backup partition** — a real ext4 disk holding a Debian image, not scratch space. Do not put the nix store or swap there.
- `vda`/`vdc` are sparse images on the phone's `/data`; their "214G" is virtual — the physical ceiling is however much free space Android reports (was 100%-full once, causing ext4 I/O errors on both disks). Keep the nix closure lean; see the trimmed `packages-droid.nix`. Host-side, `fstrim -v /` inside the VM returns sparse blocks to the phone.

### apt vs nix on the VM

Tailscale stays **apt-installed** — `tailscaled` is a system service the nix CLI can't replace. Everything else (`git`, `age`, `adb`, `tmux`, ...) is bootstrap scaffolding: the HM profile shadows it, so `apt remove` it once the first switch lands.

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

## Doing it by hand — terminal channel (what pixel-vm.sh does)

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

## Sending files to the VM — scp over Tailscale SSH, taildrop as fallback

Once the VM is on the tailnet you have two file channels (neither needs the terminal — `input`/OCR cannot carry file contents, and there is no shared `/sdcard`):

- **`scp`/`rsync` over Tailscale SSH** — preferred: works both directions, preserves perms, no inbox step. `scp file droid@100.x.x.x:~/`
- **Taildrop** — works before sshd is up (only needs tailscaled), and for pushing files *to* the VM:

```bash
# 1) push file(s) into the VM's taildrop inbox (no confirmation output on success)
tailscale file cp file1.apk file2.apk pixel-vm:
#    pixel-vm resolves by name or by 100.x.x.x

# 2) inside the VM — over ssh if it's up (preferred):
ssh droid@100.x.x.x 'sudo tailscale file get /home/droid'
#    ...or via the terminal channel:
./scripts/pixel-vm.sh send 'sudo tailscale file get /home/droid'
./scripts/pixel-vm.sh send 'ls -l /home/droid'
./scripts/pixel-vm.sh ocr      # confirm the files landed
```

Notes:
- `tailscale file cp <files> <node>:` — trailing `:` targets the node's inbox. Silent on success.
- `tailscale file get <dir>` needs sudo *inside the VM* (its inbox `/var/lib/tailscale/files` is root-owned) — but is unprivileged on boss. Inbound files to *this* machine: `tailscale file get <dir>` lands them here, no sudo.
- Pulling files *from* the VM: use `scp` over Tailscale SSH. The terminal/OCR fallback is `cat` + screenshot — only worth it for short text (that's how the first age pubkey came back, via `od` hex dump).

## Gotchas

- **`input text` quirks**: escape spaces as `\ `; avoid `|`, `>`, `$()` in commands — on this build a piped command leaked into a different app (`droiddeck`) instead of the terminal. Prefer short single commands; chain on the host side instead.
- **The terminal session drops under load** — heavy nix I/O kills the app's shell connection ("Press ⏎ to Reconnect" overlay) and takes foreground jobs with it. Anything long must run detached: `setsid nohup sh script.sh > log 2>&1 &`, or better, over ssh once Tailscale SSH is up.
- **`/sdcard` does not exist in the VM** — no shared storage with Android; file-based I/O is impossible over the terminal channel. To *send files to the VM* use taildrop, not the terminal (see below).
- **OCR is lossy** on punctuation (`£`, `1`/`l`, `0`/`O`). Verify state with commands whose output OCRs reliably (`tailscale ip -4`, `hostname`), not by eyeballing echoed commands.
- **Focus can wander**: tap inside the display before typing; if text lands in the wrong app, retap and retry. Phone display 0 (`input` without `-d`) is a different screen — never send there.
- **Remote grep is toybox** — no `-P`/`grep -oP` inside `adb shell`; use `grep -o`/`awk`. Parse locally where possible.
- **Display ids change per scrcpy session** — always re-resolve, never hardcode.
- `vm console <cid>` fails for this VM ("Failed to get VM with console") — Terminal-app VMs have no host console; don't waste time there.
