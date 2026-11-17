#!/usr/bin/env bash
# bootstrap.sh — Install Nix and activate the Home Manager configuration.
#
# This script sets up the full Nix + Home Manager environment from scratch.
# It is safe to re-run; all steps check whether they're already done.
#
# Prerequisites:
#   - curl is installed (available by default on Ubuntu/Kubuntu)
#   - You are NOT running as root (Nix is installed as a multi-user daemon)
#
# Usage:
#   ./bootstrap.sh          # activates ./nix#boss (desktop)
#   ./bootstrap.sh lord     # activates ./nix#lord (lord-ubuntu server)
#
# After this script completes, also run:
#   ansible-playbook ansible.yml --ask-become-pass
# to install system-level packages (Docker, Mullvad, KDE integration, etc.)
# that cannot be managed by Home Manager on a non-NixOS system.

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}══ $* ${NC}"; }

# ── Sanity checks ─────────────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
  error "Do not run this script as root. Nix will request sudo when needed."
  exit 1
fi

# Resolve the directory containing this script so we can reference nix/ even
# when the script is invoked from a different working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIX_CONFIG_DIR="$SCRIPT_DIR/nix"

# Flake config to activate. Default "boss" (desktop); on other hosts pass the
# config name explicitly: ./bootstrap.sh lord / ./bootstrap.sh droid
CONFIG_NAME="${1:-boss}"

if [[ ! -f "$NIX_CONFIG_DIR/flake.nix" ]]; then
  error "Could not find nix/flake.nix in $SCRIPT_DIR"
  error "Make sure you run this script from the installs repo root."
  exit 1
fi

# ── Step 1: Install Nix (Determinate Systems declarative installer) ───────────
step "Nix Package Manager"

# Set when this run installs Nix: shells (and a tmux server) started before
# now have a PATH without the Nix profile dirs, so `hms` in them fails with
# `home-manager: line N: nix: command not found`. See "Refresh existing shells".
NIX_FRESH_INSTALL=0

if command -v nix &>/dev/null; then
  success "Nix is already installed ($(nix --version))"
else
  NIX_FRESH_INSTALL=1
  info "Installing Nix via the Determinate Systems declarative installer..."
  info "This creates a receipt at /nix/receipt.json for reproducible state tracking."
  info "See https://github.com/DeterminateSystems/nix-installer for details."

  # Use --proto and --tlsv1.2 for secure download. The installer:
  #   - Sets up a multi-user Nix installation (daemon mode)
  #   - Enables the 'nix-command' and 'flakes' experimental features by default
  #   - Creates /nix/receipt.json for declarative uninstall/repair
  curl --proto '=https' --tlsv1.2 -sSf \
    https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm

  success "Nix installed."
fi

# ── Step 2: Declare cache.numtide.com on the daemon ───────────────────────────
step "Nix daemon substituters"

# nix/flake.nix's llm-agents input ships pre-built binaries on
# cache.numtide.com, and update.d/10-nix.sh age-pins that input
# (PIN_AGE_DAYS_LLM_AGENTS) to commits numtide has already published. None of
# that helps unless the *daemon* knows to query the cache — a flake's own
# nixConfig block isn't trusted for substituters — so declare it here in the
# daemon's nix.custom.conf. Without this, every llm-agents tool builds locally.
#
# The substituter list itself lives in $NIX_CONFIG_DIR/nix.custom.conf so
# new caches can be added repo-side instead of editing this script.
NIX_CUSTOM_CONF="/etc/nix/nix.custom.conf"
REPO_CUSTOM_CONF="$NIX_CONFIG_DIR/nix.custom.conf"

if [[ ! -f "$REPO_CUSTOM_CONF" ]]; then
  warn "$REPO_CUSTOM_CONF missing — skipping daemon substituter setup."
elif [[ ! -f "$NIX_CUSTOM_CONF" ]]; then
  info "Creating $NIX_CUSTOM_CONF from repo copy (needs sudo)..."
  sudo install -d /etc/nix
  sudo install -m 644 "$REPO_CUSTOM_CONF" "$NIX_CUSTOM_CONF"
  sudo systemctl restart nix-daemon.service \
    || warn "Could not restart nix-daemon — restart it manually before building."
  success "$NIX_CUSTOM_CONF initialised."
else
  # Idempotent append of any substituter/key lines not already present.
  appended=0
  while IFS= read -r line; do
    # Skip blanks/comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if ! sudo grep -qxF "$line" "$NIX_CUSTOM_CONF" 2>/dev/null; then
      info "Adding: $line"
      echo "$line" | sudo tee -a "$NIX_CUSTOM_CONF" >/dev/null
      appended=1
    fi
  done < "$REPO_CUSTOM_CONF"
  if [[ "$appended" -eq 1 ]]; then
    info "Restarting nix-daemon to pick up new substituters..."
    sudo systemctl restart nix-daemon.service \
      || warn "Could not restart nix-daemon — restart it manually before building."
    success "Substituters updated."
  else
    success "Substituters already declared."
  fi
fi

# ── Step 3: Source the Nix environment ────────────────────────────────────────
step "Sourcing Nix environment"

NIX_DAEMON_PROFILE="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
if [[ -f "$NIX_DAEMON_PROFILE" ]]; then
  # shellcheck disable=SC1090
  . "$NIX_DAEMON_PROFILE"
  success "Nix environment sourced."
else
  # Fallback: the user-level profile (single-user install)
  if [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    success "Nix user environment sourced."
  else
    error "Could not find Nix profile script. You may need to open a new terminal."
    error "Then re-run: nix run github:nix-community/home-manager -- switch --flake ./nix#$CONFIG_NAME"
    exit 1
  fi
fi

# Verify nix is now usable
if ! command -v nix &>/dev/null; then
  error "nix command not found after sourcing profile. Open a new shell and retry."
  exit 1
fi

# ── Step 4: Verify flakes are enabled (Determinate Systems enables them by default)
step "Checking flakes support"

if nix flake --help &>/dev/null 2>&1; then
  success "Flakes are enabled."
else
  warn "Flakes do not appear to be enabled. Attempting to enable via nix.conf..."
  mkdir -p "$HOME/.config/nix"
  if ! grep -q "experimental-features" "$HOME/.config/nix/nix.conf" 2>/dev/null; then
    echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"
    info "Added experimental-features to ~/.config/nix/nix.conf"
  fi
fi

# ── Step 5: Activate Home Manager ─────────────────────────────────────────────
step "Home Manager"

FLAKE_REF="$NIX_CONFIG_DIR#$CONFIG_NAME"

if command -v home-manager &>/dev/null; then
  info "home-manager found — running switch..."
  home-manager switch -b backup --flake "$FLAKE_REF"
else
  info "home-manager not found — bootstrapping via 'nix run github:nix-community/home-manager'..."
  info "This downloads home-manager and runs your configuration."
  info "(Subsequent runs will use the installed home-manager binary.)"
  nix run github:nix-community/home-manager -- switch -b backup --flake "$FLAKE_REF"
fi

success "Home Manager configuration applied."

# ── Step 6 (lord only): server-side ansible ──────────────────────────────────
# ansible/lord-ubuntu.yml targets `hosts: lord-ubuntu`, but run from the
# server itself --connection local makes the same play run in place (no SSH
# to self needed).
if [[ "$CONFIG_NAME" == "lord" ]]; then
  step "Ansible: lord-ubuntu user-level setup (local)"

  ANSIBLE_BIN="$HOME/.nix-profile/bin/ansible-playbook"
  if [[ ! -x "$ANSIBLE_BIN" ]]; then
    warn "ansible-playbook not in the new Nix profile — run later:"
    warn "  ~/.nix-profile/bin/ansible-playbook --connection local $SCRIPT_DIR/ansible/lord-ubuntu.yml"
  else
    "$ANSIBLE_BIN" --connection local "$SCRIPT_DIR/ansible/lord-ubuntu.yml"
    success "Ansible applied."
  fi
fi

# ── Refresh existing shells ──────────────────────────────────────────────────
# A running tmux server hands its own (pre-Nix) environment to every new
# pane, so "open a new terminal" isn't enough inside tmux. Push this script's
# PATH (now including the Nix profile dirs) into the server's global env.
# Panes that are already open still need `exec bash`.
if [[ "$NIX_FRESH_INSTALL" -eq 1 ]] && command -v tmux &>/dev/null; then
  # shellcheck disable=SC2033  # tmux is a real binary; `info` is our function name, not an arg to a function
  if tmux info &>/dev/null; then
    tmux set-environment -g PATH "$PATH"
    success "Updated the running tmux server's PATH (new panes will find nix)."
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Bootstrap complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Run 'exec bash' in every shell that was open before this script"
echo "     (including tmux panes and terminals inside agents like Claude Code)."
echo "     Otherwise hms fails there with 'nix: command not found'."
if [[ "$CONFIG_NAME" == "lord" ]]; then
  echo "  2. Provision the sops age key (see docs/system/lord-ubuntu-home.md):"
  echo "       mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt"
  echo "       then add its pubkey to .sops.yaml on the desktop + sops updatekeys"
elif [[ "$CONFIG_NAME" == "droid" ]]; then
  echo "  2. Provision the sops age key (plaintext is fine on the VM):"
  echo "       mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt"
  echo "     then on the desktop: add the pubkey to .sops.yaml's &droid entry,"
  echo "     create nix/secrets/ai-droid.yaml (freellmapi/refuseless keys), and"
  echo "     sops updatekeys. Re-run hms afterwards."
else
  echo "  2. Run the Ansible playbook for system-level packages."
  echo "     ansible-playbook is now available from your Nix profile:"
  echo "       ansible-playbook $SCRIPT_DIR/ansible.yml --ask-become-pass"
  echo "     This installs KDE integration, system services, Docker, Mullvad VPN,"
  echo "     and other tools that require root or system-level setup."
  echo "  3. Set up Flatpak apps (reinstall from ~/.var/app if migrating):"
  echo "       $SCRIPT_DIR/flatpak.sh"
  echo "  4. Check distrobox containers: distrobox list"
  echo "  5. Future updates: update-all"
fi
echo ""
echo "  Nix receipt (for uninstall/repair): /nix/receipt.json"
echo "  Home Manager config:               $NIX_CONFIG_DIR"
