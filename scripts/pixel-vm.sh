#!/bin/bash
# scripts/pixel-vm.sh
#
# Drive the Android "Linux Terminal" app (AVF/crosvm Debian VM) on a Pixel
# phone from this machine over adb. The VM's shell is only reachable through
# the Terminal app's UI — `vm console`/`vm start-adbd` only work for VMs
# launched via the `vm` tool — so this script types commands onto the scrcpy
# virtual display where the app runs and reads output back by screenshotting
# that display and OCR'ing it with tesseract.
#
# Subcommands:
#   status            Show tailnet state inside the VM
#   join              Enrol the VM on the Headscale tailnet (auto-mints a
#                     reusable pre-auth key on the Headscale VPS via
#                     `ssh don@headscale`; falls back to printing the login
#                     URL if the key can't be obtained)
#   send CMD ...      Type CMD into the VM shell and press Enter
#   screenshot [PATH] Save a PNG of the VM terminal display (default /tmp)
#   ocr               Print an OCR'd transcript of the current screen
#
# Env:
#   ADB_SERIAL   adb serial to use (default: auto if exactly one device)
#   VM_HOSTNAME  tailnet name for the VM (default: pixel-vm)
#   HS_SSH       ssh target for minting pre-auth keys (default: don@headscale)
#   LOGIN_SERVER Headscale control URL (default: https://15-hs.example.com)
#
# Requirements: adb (device connected), tesseract (OCR), scrcpy session
# already showing the Terminal app (the VM display only exists while scrcpy
# or another virtual-display client presents it).

set -euo pipefail

LOGIN_SERVER="${LOGIN_SERVER:-https://15-hs.example.com}"
VM_HOSTNAME="${VM_HOSTNAME:-pixel-vm}"
HS_SSH="${HS_SSH:-don@headscale}"
VM="/apex/com.android.virt/bin/vm"

ADB=(adb)
[[ -n "${ADB_SERIAL:-}" ]] && ADB+=( -s "$ADB_SERIAL" )
"${ADB[@]}" devices | grep -q '	device$' || { echo "no adb device connected" >&2; exit 1; }

# ── Locate the scrcpy display that hosts the Terminal app ─────────────────
# Logical display id (for `input -d`) and SurfaceFlinger id (for `screencap -d`)
# are different numbers; resolve both each run since they change per session.
resolve_display() {
    # find the input logical displayId whose focused window is the terminal
    DISPLAY_LOGICAL=$("${ADB[@]}" shell 'dumpsys input | grep "virtualization.terminal/.new2" | grep -o "displayId=[0-9]*" | grep -o "[0-9]*" | head -1')
    if [[ -z "$DISPLAY_LOGICAL" ]]; then
        echo "Terminal app not found on any display — is the scrcpy window open with the Terminal app showing?" >&2; exit 1
    fi
    # uniqueId of that display, e.g. virtual:com.android.shell,2000,scrcpy,21
    DISPLAY_UNIQUE=$("${ADB[@]}" shell "dumpsys input | grep \"displayId=${DISPLAY_LOGICAL}, uniqueId\"" \
        | grep -o "virtual:.*,scrcpy,[0-9]*" | head -1)
    # map uniqueId → SurfaceFlinger display id for screencap
    DISPLAY_SF=$("${ADB[@]}" shell 'dumpsys SurfaceFlinger --display-id' \
        | grep -F "$DISPLAY_UNIQUE" | grep -o 'Display [0-9]*' | grep -o '[0-9]*' | head -1)
    if [[ -z "$DISPLAY_SF" ]]; then
        echo "Could not map display $DISPLAY_LOGICAL to a SurfaceFlinger id" >&2; exit 1
    fi
}

# Type a command into the VM terminal (tap to focus, text, Enter).
vm_type() {
    local cmd="$1"
    "${ADB[@]}" shell input -d "$DISPLAY_LOGICAL" tap 900 500
    sleep 0.4
    # `input text` treats \  as a literal space; keep the VM-side command free
    # of pipes/redirection (they trigger system-app quirks seen on this build).
    "${ADB[@]}" shell input -d "$DISPLAY_LOGICAL" text "${cmd// /\\ }"
    "${ADB[@]}" shell input -d "$DISPLAY_LOGICAL" keyevent 66
}

shot() {
    local out="$1"
    "${ADB[@]}" exec-out screencap -p -d "$DISPLAY_SF" > "$out"
}

ocr() {
    tesseract "$1" - 2>/dev/null | sed 's/[[:space:]]*$//' | grep -v '^$'
}

# ── checks ────────────────────────────────────────────────────────────────
check_vm_running() {
    CID=$("${ADB[@]}" shell "$VM list" | grep -o 'cid: [0-9]*' | grep -o '[0-9]*' | head -1)
    if [[ -z "$CID" ]]; then
        echo "No AVF VM running — open the Linux Terminal app first" >&2; exit 1
    fi
}

mint_authkey() {
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HS_SSH" \
        'sudo docker exec headscale headscale preauthkeys create --user 1 --reusable --expiration 24h' \
        | grep -o 'hskey-auth-[A-Za-z0-9_-]*' || true
}

cmd_status() {
    check_vm_running; resolve_display
    vm_type 'tailscale status'
    sleep 3
    shot /tmp/pixel-vm.png
    ocr /tmp/pixel-vm.png | tail -12
}

cmd_join() {
    check_vm_running; resolve_display
    local key
    key=$(mint_authkey)
    if [[ -z "$key" ]]; then
        echo "Could not mint a pre-auth key via ssh $HS_SSH" >&2
        echo "Falling back to interactive login: running tailscale up; watch for a URL." >&2
        vm_type "sudo tailscale up --login-server ${LOGIN_SERVER} --hostname ${VM_HOSTNAME}"
        sleep 10
        shot /tmp/pixel-vm.png
        ocr /tmp/pixel-vm.png | tail -15
        echo
        echo "If a https:// URL appears above, open it and approve the node." >&2
        return
    fi
    echo "Auth key minted. Joining as '${VM_HOSTNAME}' on ${LOGIN_SERVER}..."
    vm_type "sudo tailscale up --login-server ${LOGIN_SERVER} --auth-key ${key} --hostname ${VM_HOSTNAME}"
    sleep 12
    # verify
    vm_type 'tailscale ip -4'
    sleep 3
    shot /tmp/pixel-vm.png
    ocr /tmp/pixel-vm.png | tail -8
}

cmd_send() {
    resolve_display
    vm_type "$*"
    sleep 1
}

cmd_screenshot() {
    resolve_display
    local out="${1:-/tmp/pixel-vm-screen.png}"
    shot "$out"
    echo "$out"
}

cmd_ocr() {
    resolve_display
    shot /tmp/pixel-vm.png
    ocr /tmp/pixel-vm.png
}

case "${1:-}" in
    status)      cmd_status ;;
    join)        cmd_join ;;
    send)        shift; cmd_send "$@" ;;
    screenshot)  cmd_screenshot "${2:-}" ;;
    ocr)         cmd_ocr ;;
    *) sed -n '2,33p' "$0"; exit 1 ;;
esac
