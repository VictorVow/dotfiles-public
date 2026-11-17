#!/bin/bash
# nix/dotfiles/agent-skills/android-linux-terminal-automation/scripts/vm-bootstrap.sh
#
# Bootstrap a FRESH Debian install in the Pixel AVF "Linux Terminal" VM into a
# tailnet member running the repo's Home Manager config. The fresh VM has no
# sshd and no tailscale — the only channel is the scrcpy terminal via
# pixel-vm.sh — so the script drives that channel until Tailscale SSH is up,
# then switches to plain ssh.
#
# What it does, in order:
#   1. apt install tailscale (adds pkgs.tailscale.com repo), join the Headscale
#      tailnet, enable Tailscale SSH (`tailscale set --ssh`).
#   2. Provision memory: persistent 4G /swapfile (fstab) + transient 2G zram
#      (the VM has ~1G RAM; nix eval/build OOMs without ~6G total swap).
#   3. apt install git + age (needed before the first HM switch; delete them
#      afterwards — the nix profile provides both).
#   4. Generate ~/.config/sops/age/keys.txt over ssh, print the pubkey.
#   5. Taildrop a tarball of this repo to the VM, extract to ~/installs,
#      `git init` + `git add -A` (flakes ignore untracked files).
#   6. With --run-bootstrap: run ./bootstrap.sh <host> detached to a log.
#
# Usage:
#   vm-bootstrap.sh [--host droid] [--skip-bootstrap|--run-bootstrap]
#
# Env:
#   VM_HOSTNAME  tailnet name (default: pixel-vm)
#   VM_USER      VM login user (default: droid)
#   VM_REPO      repo dir inside the VM (default: /home/$VM_USER/installs)
#   SWAP_GB      /swapfile size (default: 4)
#   ZRAM_MB      extra zram swap (default: 2048; 0 disables)
#   REPO_DIR     local installs repo (default: two dirs up from this script)
#   HS_SSH / LOGIN_SERVER / ADB_SERIAL   passed through to pixel-vm.sh
#
# Requires: adb + scrcpy terminal channel working (pixel-vm.sh), ssh,
# tailscale, tar on this machine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIXEL_VM="$SCRIPT_DIR/pixel-vm.sh"

VM_HOSTNAME="${VM_HOSTNAME:-pixel-vm}"
VM_USER="${VM_USER:-droid}"
VM_HOME="/home/$VM_USER"
VM_REPO="${VM_REPO:-$VM_HOME/installs}"
SWAP_GB="${SWAP_GB:-4}"
ZRAM_MB="${ZRAM_MB:-2048}"
REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"
HOST_NAME="droid"
RUN_BOOTSTRAP=ask

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)           HOST_NAME="$2"; shift 2 ;;
    --run-bootstrap)  RUN_BOOTSTRAP=yes; shift ;;
    --skip-bootstrap) RUN_BOOTSTRAP=no; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

step() { echo; echo "=== $* ==="; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── Terminal-channel helpers (only usable until ssh is up) ──────────────────
# No pipes/redirects/metachars survive `input text` — one simple command each.
vm_send() { "$PIXEL_VM" send "$1"; sleep "${2:-2}"; }
vm_ocr()  { "$PIXEL_VM" ocr | tail -"${1:-8}"; }

# ── ssh helpers (once tailscale ssh is up) ──────────────────────────────────
KNOWN_HOSTS="${TMPDIR:-/tmp}/vm-bootstrap-known_hosts"
VM_IP=""

ssh_vm() {
  ssh -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=accept-new \
      -o BatchMode=yes -o ConnectTimeout=15 "$VM_USER@$VM_IP" "$@"
}

resolve_ip() {
  # From the host's own tailnet view — no terminal OCR needed.
  VM_IP=$(tailscale status --json 2>/dev/null \
      | grep -oE '"HostName": ?"'"$VM_HOSTNAME"'"|"TailscaleIPs": ?\["[0-9.]+"' \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true
  if [[ -z "$VM_IP" ]]; then
    VM_IP=$(tailscale status 2>/dev/null | awk -v h="$VM_HOSTNAME" '$2==h {print $1; exit}')
  fi
  [[ -n "$VM_IP" ]] || die "could not resolve $VM_HOSTNAME's tailnet IP"
  echo "VM tailnet IP: $VM_IP"
}

# ── Phase 1: tailscale + tailnet + tailscale ssh (terminal channel) ─────────
phase_tailscale() {
  step "Phase 1: install tailscale + join tailnet (terminal channel)"
  vm_send 'sudo apt update' 20

  # pkgs.tailscale.com repo — the trixie line works on the AVF image.
  vm_send 'curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list -o /tmp/ts.list' 8
  vm_send 'sudo tee /etc/apt/sources.list.d/tailscale.list < /tmp/ts.list' 3
  vm_send 'curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg -o /tmp/ts.gpg' 8
  vm_send 'sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg < /tmp/ts.gpg' 3
  vm_send 'sudo apt-get update' 20
  vm_send 'sudo apt-get install -y tailscale' 30
  vm_send 'sudo systemctl enable --now tailscaled' 5

  # Reuse pixel-vm.sh join (mints the Headscale pre-auth key).
  "$PIXEL_VM" join

  vm_send 'sudo tailscale set --ssh=true' 4
  resolve_ip

  echo "Waiting for tailscale sshd on $VM_IP:22..."
  for _ in $(seq 1 12); do
    ssh-keyscan -t ed25519 -T 5 "$VM_IP" >> "$KNOWN_HOSTS" 2>/dev/null && break
    sleep 5
  done
  ssh_vm 'echo SSH_OK' | grep -q SSH_OK || die "ssh to $VM_USER@$VM_IP failed"
  echo "Tailscale SSH is up."
}

# ── Phase 2: swap + zram ────────────────────────────────────────────────────
# Decision: persistent = a real /swapfile on vda (fstab) — survives reboots,
# no kernel module needed at boot. Transient = extra zram for eval spikes
# (VM image already has ~240M zram0; we add more capacity at runtime only).
phase_memory() {
  step "Phase 2: swap (${SWAP_GB}G file, persistent) + zram (${ZRAM_MB}M, runtime)"
  ssh_vm "
    set -e
    if ! grep -q '^/swapfile' /etc/fstab; then
      sudo fallocate -l ${SWAP_GB}G /swapfile
      sudo chmod 600 /swapfile
      sudo mkswap /swapfile >/dev/null
      echo '/swapfile none swap sw,pri=50 0 0' | sudo tee -a /etc/fstab
    fi
    grep -q '/swapfile' /proc/swaps || sudo /sbin/swapon -p 50 /swapfile
    if [ '${ZRAM_MB}' != '0' ] && sudo modprobe zram 2>/dev/null; then
      dev=\$(sudo zramctl -f -s ${ZRAM_MB}M 2>/dev/null || true)
      if [ -n \"\$dev\" ]; then
        sudo mkswap \"\$dev\" >/dev/null
        sudo /sbin/swapon -p 100 \"\$dev\"
        echo \"zram swap on \$dev (transient — recreate after reboot if needed)\"
      fi
    fi
    cat /proc/swaps
    free -m | tail -1
  "
}

# ── Phase 3: apt prereqs for the nix bootstrap ─────────────────────────────
phase_prereqs() {
  step "Phase 3: apt install git + age (deleted later; nix profile owns them)"
  ssh_vm 'sudo apt-get update && sudo apt-get install -y git age 2>&1 | tail -3'
}

# ── Phase 4: sops age key ──────────────────────────────────────────────────
phase_agekey() {
  step "Phase 4: generate sops age key on the VM"
  ssh_vm "
    mkdir -p $VM_HOME/.config/sops/age
    [ -f $VM_HOME/.config/sops/age/keys.txt ] || age-keygen -o $VM_HOME/.config/sops/age/keys.txt
    chmod 600 $VM_HOME/.config/sops/age/keys.txt
    age-keygen -y $VM_HOME/.config/sops/age/keys.txt
  " | tee /tmp/vm-droid-pubkey.txt
  echo
  echo ">>> VM age pubkey (saved to /tmp/vm-droid-pubkey.txt):"
  cat /tmp/vm-droid-pubkey.txt
}

# ── Phase 5: repo tarball via taildrop ─────────────────────────────────────
phase_repo() {
  step "Phase 5: taildrop repo tarball -> $VM_REPO"
  local tgz
  tgz=$(mktemp --suffix=-installs.tgz)
  tar czf "$tgz" --exclude=.git --exclude=node_modules -C "$REPO_DIR" .
  tailscale file cp "$tgz" "$VM_HOSTNAME":
  echo "sent $(du -h "$tgz" | cut -f1) tarball"
  ssh_vm "
    set -e
    sudo tailscale file get $VM_HOME
    mkdir -p $VM_REPO
    tar xzf $VM_HOME/$(basename "$tgz") -C $VM_REPO
    rm $VM_HOME/$(basename "$tgz")
    sudo chown -R $VM_USER $VM_REPO
    cd $VM_REPO
    [ -d .git ] || git init -q
    git add -A
    git ls-files | wc -l
  "
  rm -f "$tgz"
}

# ── Phase 6: run repo bootstrap.sh (detached — terminal drops under load) ──
phase_bootstrap() {
  step "Phase 6: run $VM_REPO/bootstrap.sh $HOST_NAME (detached)"
  ssh_vm "
    cd $VM_REPO
    cat > $VM_HOME/vm-bootstrap-run.sh <<'EOF'
#!/bin/sh
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null
exec ./bootstrap.sh $HOST_NAME
EOF
    setsid nohup sh $VM_HOME/vm-bootstrap-run.sh > $VM_HOME/bootstrap.log 2>&1 < /dev/null &
    sleep 2
    pgrep -f bootstrap | wc -l
  "
  echo "Bootstrap running detached. Watch with:"
  echo "  ssh -o UserKnownHostsFile=$KNOWN_HOSTS $VM_USER@$VM_IP 'tail -f $VM_HOME/bootstrap.log'"
  echo "Then: tail -3 $VM_HOME/bootstrap.log to check for completion."
}

main() {
  [[ -x "$PIXEL_VM" ]] || die "pixel-vm.sh not found at $PIXEL_VM"
  adb devices | grep -q '	device$' || die "no adb device connected"

  phase_tailscale
  phase_memory
  phase_prereqs
  phase_agekey
  phase_repo

  case "$RUN_BOOTSTRAP" in
    yes) phase_bootstrap ;;
    ask)
      echo
      read -r -p "Run $VM_REPO/bootstrap.sh $HOST_NAME now? [Y/n] " a
      [[ "${a:-y}" =~ ^[Nn] ]] || phase_bootstrap
      ;;
  esac

  step "Manual steps remaining (on this machine)"
  cat <<EOF
1. Add the VM pubkey (see above) to .sops.yaml as &droid, add *droid to the
   ai-droid rule, then:  sops updatekeys nix/secrets/ai-droid.yaml
   and fill the freellmapi/refuseless values in that file.
2. Re-sync ai-droid.yaml to the VM (taildrop + git add), re-run hms there.
3. OPTIONAL cleanup once the nix profile is live:
     ssh ... 'sudo apt-get remove -y git age && sudo apt-get autoremove -y'
4. Commit the repo changes.
EOF
}

main
