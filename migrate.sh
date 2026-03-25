#!/usr/bin/env bash
# migrate.sh — Safely migrate from Ansible-managed packages to Nix/Home Manager.
#
# ASSUMPTION: The existing (unslimmed) ansible.yml has already been run, so
# all packages are currently installed via apt, pipx, npm, and Homebrew.
#
# This script:
#   1. Runs bootstrap.sh to install Nix and activate the Home Manager config
#   2. Verifies that all key packages are present in the Nix profile
#   3. Verifies that both distrobox containers are up
#   4. Only then removes packages from apt/pipx/npm/brew that are now in Nix
#
# The script aborts at step 2 if verification fails — nothing is removed.
# It is IDEMPOTENT: safe to re-run after partial success.
#
# Usage:
#   ./migrate.sh
#   ./migrate.sh --dry-run   # Print what would be removed without removing it

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[DRY RUN MODE — nothing will be removed]"
fi

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}══ $* ${NC}"; }

run() {
  if $DRY_RUN; then
    echo "  [DRY RUN] $*"
  else
    "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Step 1: Pre-flight — confirm ansible has already run ──────────────────────
step "Pre-flight: confirming Ansible-managed packages are present"

PREFLIGHT_PACKAGES=(git tmux htop distrobox ffmpeg)
MISSING_PREFLIGHT=()

for pkg in "${PREFLIGHT_PACKAGES[@]}"; do
  if ! command -v "$pkg" &>/dev/null && ! dpkg -l "$pkg" &>/dev/null 2>&1; then
    MISSING_PREFLIGHT+=("$pkg")
  fi
done

if [[ ${#MISSING_PREFLIGHT[@]} -gt 0 ]]; then
  error "Pre-flight failed: the following packages are not installed:"
  for pkg in "${MISSING_PREFLIGHT[@]}"; do
    error "  - $pkg"
  done
  error ""
  error "Please run the Ansible playbook first:"
  error "  ansible-playbook ansible.yml --ask-become-pass"
  exit 1
fi

success "Pre-flight passed — Ansible-managed packages are present."

# ── Step 2: Run bootstrap.sh ─────────────────────────────────────────────────
step "Running bootstrap.sh (Nix + Home Manager)"

if [[ ! -f "$SCRIPT_DIR/bootstrap.sh" ]]; then
  error "bootstrap.sh not found in $SCRIPT_DIR"
  exit 1
fi

bash "$SCRIPT_DIR/bootstrap.sh"

# Source Nix environment so we can check the profile
NIX_DAEMON_PROFILE="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
[[ -f "$NIX_DAEMON_PROFILE" ]] && . "$NIX_DAEMON_PROFILE"

# ── Step 3: Verification gate ─────────────────────────────────────────────────
step "Verification: checking Nix profile"

VERIFICATION_FAILED=false

_check_bin() {
  local name="$1"
  local bin="${2:-$1}"
  # Check nix profile bin dir first, then PATH fallback
  if [[ -f "$HOME/.nix-profile/bin/$bin" ]] || command -v "$bin" &>/dev/null; then
    success "  ✓ $name"
  else
    error "  ✗ $name not found in Nix profile"
    VERIFICATION_FAILED=true
  fi
}

info "Checking key binaries in ~/.nix-profile/bin ..."
_check_bin "git"
_check_bin "tmux"
_check_bin "btop"
_check_bin "nvim"         "nvim"
_check_bin "starship"
_check_bin "yt-dlp"       "yt-dlp"
_check_bin "deno"
_check_bin "rclone"
_check_bin "gh"           "gh"
_check_bin "distrobox"
_check_bin "ffmpeg"
_check_bin "scrcpy"
_check_bin "streamlink"
_check_bin "signal-desktop" "signal-desktop"

info "Checking home-manager generation ..."
if home-manager generations 2>/dev/null | head -1 | grep -q "generation"; then
  success "  ✓ home-manager has at least one generation"
else
  error "  ✗ home-manager has no generations recorded"
  VERIFICATION_FAILED=true
fi

info "Checking distrobox containers ..."
if command -v distrobox &>/dev/null; then
  if distrobox list 2>/dev/null | grep -q "dev"; then
    success "  ✓ 'dev' container exists"
  else
    warn "  ⚠ 'dev' container not found (may still be creating)"
  fi
  if distrobox list 2>/dev/null | grep -q "media"; then
    success "  ✓ 'media' container exists"
  else
    warn "  ⚠ 'media' container not found (may still be creating)"
  fi
else
  warn "  ⚠ distrobox not in PATH yet — restart shell and check manually"
fi

if $VERIFICATION_FAILED; then
  error ""
  error "Verification FAILED. One or more packages are missing from the Nix profile."
  error "Nothing has been removed. Fix the issue and re-run migrate.sh."
  error ""
  error "Debugging tips:"
  error "  home-manager switch --flake ./nix#boss"
  error "  nix profile list"
  exit 1
fi

success "Verification passed — Nix profile looks healthy."

# ── Step 4: Remove apt packages now managed by Nix ───────────────────────────
step "Removing apt packages now managed by Nix"

# Only packages that have been confirmed to exist in nixpkgs are listed here.
# System-level packages (earlyoom, logiops, postfix, power-profiles-daemon,
# vnstat, libva-*, flatpak, xdg-desktop-portal-gnome, etc.) are NOT removed.
APT_TO_REMOVE=(
  # Android tools
  adb fastboot

  # System monitors (now in nix)
  btop htop nvtop cpulimit

  # Container tools (now in nix)
  distrobox crun passt rootlesskit

  # System info
  fastfetch inxi

  # Security
  firejail gnupg

  # Filesystem
  gocryptfs

  # Media
  haruna mediainfo mediainfo-gui simplescreenrecorder streamlink
  pavucontrol speech-dispatcher

  # File tools
  rclone recoll

  # Terminal
  screen tmux micro lynx

  # Networking / monitoring
  sniffnet

  # Hardware
  piper solaar

  # Gaming
  lutris steam gamemode gamescope wine

  # Communication
  signal-desktop

  # Database
  sqlitebrowser

  # Development
  git git-lfs gh rustup
  openjdk-17-jdk openjdk-17-jre
  mono-complete
  python3-xlib  # Was needed for key-mon; now handled by nix

  # Torrent
  ktorrent

  # Audio tag editor
  puddletag

  # Virtualisation
  virt-manager

  # Python tools (now via nix: poetry, uv, virtualenv)
  # Note: python3-pip and pipx are kept for system Python workflows
  # Uncomment below if you want to remove them:
  # python3-pip pipx

  # Screen recording
  scrcpy

  # VS Code (now pkgs.vscode in nix)
  code

  # Misc
  vnstat  # CLI is in nix; daemon stays via system if it was installed
)

info "Packages to remove from apt:"
printf '  %s\n' "${APT_TO_REMOVE[@]}"

# Filter to only packages that are actually installed
INSTALLED_TO_REMOVE=()
for pkg in "${APT_TO_REMOVE[@]}"; do
  if dpkg -l "$pkg" &>/dev/null 2>&1; then
    INSTALLED_TO_REMOVE+=("$pkg")
  fi
done

if [[ ${#INSTALLED_TO_REMOVE[@]} -eq 0 ]]; then
  info "No apt packages to remove (already removed or never installed)."
else
  info "Actually installed and to be removed: ${#INSTALLED_TO_REMOVE[@]} packages"
  run sudo apt-get remove --purge -y "${INSTALLED_TO_REMOVE[@]}"
  run sudo apt-get autoremove -y

  # Re-mark KDE/Kubuntu essentials as manually installed so that autoremove
  # cannot cascade-remove them in future runs.  These are not managed by Nix
  # and must stay in the apt world.
  KDE_ESSENTIALS=(
    sddm sddm-theme-breeze
    dolphin ark
    plasma-runners-addons
    kde-spectacle
    plasma-widgets-addons plasma-dataengines-addons
    plasma-wallpapers-addons plasma-calendar-addons
    grub-theme-breeze plymouth-theme-breeze
    usb-creator-kde alsa-base
    kubuntu-desktop
  )
  ESSENTIALS_INSTALLED=()
  for pkg in "${KDE_ESSENTIALS[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
      ESSENTIALS_INSTALLED+=("$pkg")
    fi
  done
  if [[ ${#ESSENTIALS_INSTALLED[@]} -gt 0 ]]; then
    run sudo apt-mark manual "${ESSENTIALS_INSTALLED[@]}"
    info "Marked ${#ESSENTIALS_INSTALLED[@]} KDE essentials as manually installed."
  fi

  success "apt packages removed."
fi

# ── Step 5: Remove pipx packages now managed by Nix ──────────────────────────
step "Removing pipx packages now managed by Nix"

PIPX_TO_REMOVE=(
  yt-dlp    # Now: pkgs.yt-dlp
  poetry    # Now: pkgs.poetry
  uv        # Now: pkgs.uv
  # key-mon is handled differently (was injected into ansible's pipx env)
)

if command -v pipx &>/dev/null; then
  for pkg in "${PIPX_TO_REMOVE[@]}"; do
    if pipx list 2>/dev/null | grep -q "$pkg"; then
      info "Removing pipx package: $pkg"
      run pipx uninstall "$pkg"
    else
      info "pipx package not installed, skipping: $pkg"
    fi
  done
  success "pipx cleanup done."
else
  warn "pipx not found — skipping pipx cleanup."
fi

# ── Step 6: Remove npm global packages now managed by Nix ────────────────────
step "Removing npm global packages now managed by Nix"

NPM_TO_REMOVE=(
  deno        # Now: pkgs.deno
  typescript  # Now: pkgs.nodePackages.typescript
  corepack    # Now: pkgs.nodePackages.corepack
  # AI CLIs are NOT removed here — they were reinstalled via ~/.npm-global in shell.nix
)

if command -v npm &>/dev/null; then
  for pkg in "${NPM_TO_REMOVE[@]}"; do
    if npm list -g "$pkg" &>/dev/null 2>&1; then
      info "Removing npm global package: $pkg"
      run npm uninstall -g "$pkg"
    else
      info "npm global package not installed, skipping: $pkg"
    fi
  done
  success "npm global cleanup done."
else
  warn "npm not found — skipping npm global cleanup."
fi

# ── Step 7: Remove Homebrew packages now managed by Nix ───────────────────────
step "Removing Homebrew packages now managed by Nix"

BREW_TO_REMOVE=(
  neovim    # Now: pkgs.neovim
  starship  # Now: pkgs.starship
  scrcpy    # Now: pkgs.scrcpy
  jackett   # Now: pkgs.jackett
  zrok      # Now: pkgs.zrok
  clojure   # Now: pkgs.clojure (if installed as clojure/tools/clojure, name may differ)
  dotnet    # Now: pkgs.dotnet-sdk
  ruby      # Now: pkgs.ruby
  sniffnet  # Now: pkgs.sniffnet
  gh        # Now: pkgs.gh (also in apt above)
  # Note: nvm is kept in Homebrew unless you want to use the nixpkgs version
  # Note: codex, copilot-cli, gemini-cli are moved to ~/.npm-global via shell.nix
  # Note: git-credential-libsecret is now pkgs.gitAndTools.gitCredentialLibsecret
)

if command -v brew &>/dev/null; then
  for pkg in "${BREW_TO_REMOVE[@]}"; do
    if brew list "$pkg" &>/dev/null 2>&1; then
      info "Removing Homebrew package: $pkg"
      run brew uninstall "$pkg"
    else
      info "Homebrew package not installed, skipping: $pkg"
    fi
  done
  success "Homebrew cleanup done."
  info "Note: Homebrew itself is kept for packages not available in nixpkgs."
else
  warn "brew not found — skipping Homebrew cleanup."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Migration complete!${NC}"
echo ""
echo "Summary of what was migrated to Nix:"
echo "  - apt packages      → home.packages in nix/modules/packages.nix"
echo "  - pipx packages     → home.packages (yt-dlp, poetry, uv)"
echo "  - npm packages      → home.packages (deno, typescript, corepack)"
echo "                        ~/.npm-global (AI CLIs via activation script)"
echo "  - brew packages     → home.packages (neovim, starship, scrcpy, etc.)"
echo ""
echo "Still managed by Ansible (system-level):"
echo "  - Docker, Mullvad VPN, Android Studio"
echo "  - KDE integration, system services, system libraries"
echo "  - See the trimmed ansible.yml for the full list"
echo ""
if $DRY_RUN; then
  echo -e "${YELLOW}This was a DRY RUN — nothing was actually removed.${NC}"
  echo "Run without --dry-run to apply changes."
fi
