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
#   ./bootstrap.sh
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

if [[ ! -f "$NIX_CONFIG_DIR/flake.nix" ]]; then
  error "Could not find nix/flake.nix in $SCRIPT_DIR"
  error "Make sure you run this script from the installs repo root."
  exit 1
fi

# ── Step 1: Install Nix (Determinate Systems declarative installer) ───────────
step "Nix Package Manager"

if command -v nix &>/dev/null; then
  success "Nix is already installed ($(nix --version))"
else
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

# ── Step 2: Source the Nix environment ────────────────────────────────────────
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
    error "Then re-run: nix run home-manager/master -- switch --flake ./nix#boss"
    exit 1
  fi
fi

# Verify nix is now usable
if ! command -v nix &>/dev/null; then
  error "nix command not found after sourcing profile. Open a new shell and retry."
  exit 1
fi

# ── Step 3: Verify flakes are enabled (Determinate Systems enables them by default)
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

# ── Step 4: Activate Home Manager ─────────────────────────────────────────────
step "Home Manager"

FLAKE_REF="$NIX_CONFIG_DIR#boss"

if command -v home-manager &>/dev/null; then
  info "home-manager found — running switch..."
  home-manager switch --flake "$FLAKE_REF"
else
  info "home-manager not found — bootstrapping via 'nix run'..."
  info "This downloads home-manager and runs your configuration."
  info "(Subsequent runs will use the installed home-manager binary.)"
  nix run home-manager/master -- switch --flake "$FLAKE_REF"
fi

success "Home Manager configuration applied."

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Bootstrap complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal (or run: source ~/.bashrc) to pick up PATH changes"
echo "  2. Run the trimmed Ansible playbook for system-level packages:"
echo "       ansible-playbook ansible.yml --ask-become-pass"
echo "  3. Check distrobox containers: distrobox list"
echo "  4. Future updates: run 'hms' (alias) or home-manager switch"
echo ""
echo "  Nix receipt (for uninstall/repair): /nix/receipt.json"
echo "  Home Manager config:               $NIX_CONFIG_DIR"
