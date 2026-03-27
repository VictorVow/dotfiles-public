#!/usr/bin/env bash
# update.sh — Update all packages across every package manager.
#
# Replaces the daily `ansible-playbook ansible.yml` run that previously handled
# package upgrades. Covers:
#
#   1. Nix / Home Manager  — flake.lock update + home-manager switch
#   2. apt                 — system packages (docker, KDE libs, etc.)
#   3. Homebrew            — remaining brew packages not in Nix
#   4. npm globals         — AI CLI tools installed to ~/.npm-global
#   5. Flatpak             — user Flatpak apps
#   6. pipx                — any remaining system pipx packages
#   7. Distrobox           — OS packages inside containers
#
# Usage:
#   ./update.sh                 # Full update (all managers)
#   ./update.sh --no-nix        # Skip Nix flake update (faster, uses locked versions)
#   ./update.sh --no-distrobox  # Skip container OS upgrades
#   ./update.sh --dry-run       # Print what would run without executing
#
# Cron example (daily at 10:00):
#   0 10 * * * /home/boss/Documents/ESSENTIALS/installs/update.sh >> /tmp/update.log 2>&1

set -euo pipefail

# ── Options ───────────────────────────────────────────────────────────────────
UPDATE_NIX=true
UPDATE_DISTROBOX=true
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --no-nix)        UPDATE_NIX=false ;;
    --no-distrobox)  UPDATE_DISTROBOX=false ;;
    --dry-run)       DRY_RUN=true ;;
    --help|-h)
      grep '^#' "$0" | head -20 | sed 's/^# \?//'
      exit 0
      ;;
  esac
done

# ── Colours & helpers ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Track per-step results for the summary
declare -A RESULTS=()

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
skipped() { echo -e "${DIM}[SKIP]${NC}  $*"; }

step() {
  echo ""
  echo -e "${CYAN}${BOLD}━━━ $* ━━━${NC}"
}

run() {
  if $DRY_RUN; then
    echo -e "  ${DIM}[dry-run] $*${NC}"
  else
    "$@"
  fi
}

# Run a step and record whether it succeeded or failed/was-skipped.
# Usage: run_step <label> <command...>
run_step() {
  local label="$1"; shift
  local start; start=$(date +%s)

  if $DRY_RUN; then
    echo -e "  ${DIM}[dry-run] $*${NC}"
    RESULTS["$label"]="skipped (dry-run)"
    return 0
  fi

  if "$@" 2>&1; then
    local elapsed=$(( $(date +%s) - start ))
    RESULTS["$label"]="✓ ${elapsed}s"
  else
    RESULTS["$label"]="✗ failed"
    warn "$label failed — continuing with remaining updates."
  fi
}

# ── Setup ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIX_FLAKE_DIR="$SCRIPT_DIR/nix"

START_TIME=$(date +%s)
echo ""
echo -e "${BOLD}System Update — $(date '+%Y-%m-%d %H:%M:%S')${NC}"
$DRY_RUN && echo -e "${YELLOW}[DRY RUN MODE — nothing will be changed]${NC}"

# Source Nix environment so nix/home-manager commands are available
NIX_DAEMON_PROFILE="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
[[ -f "$NIX_DAEMON_PROFILE" ]] && . "$NIX_DAEMON_PROFILE"

# Source Homebrew environment if installed
if [[ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# npm global prefix for AI CLIs (mirrors shell.nix sessionVariables)
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$HOME/.nix-profile/bin:$HOME/.cargo/bin:$PATH"

# ── 1. Nix + Home Manager ────────────────────────────────────────────────────
step "1/7  Nix + Home Manager"

if ! command -v nix &>/dev/null; then
  warn "nix not found — skipping Nix updates. Run ./bootstrap.sh first."
  RESULTS["Nix"]="skipped (not installed)"
else
  if $UPDATE_NIX; then
    # Update flake.lock to pull latest commits from nixpkgs-unstable and
    # home-manager. This is what actually updates package versions — without
    # this step, home-manager switch just re-applies the locked versions.
    info "Updating flake.lock (fetching latest nixpkgs-unstable + home-manager)..."
    run_step "Nix flake update" nix flake update --flake "$NIX_FLAKE_DIR"
  else
    info "Skipping flake.lock update (--no-nix). Using locked package versions."
    RESULTS["Nix flake update"]="skipped (--no-nix)"
  fi

  # Apply the (possibly updated) Home Manager configuration.
  # This installs new packages, updates changed ones, and runs activation scripts
  # (including distrobox container creation and npm AI CLI installation).
  info "Applying Home Manager configuration..."
  run_step "home-manager switch" \
    home-manager switch --flake "$NIX_FLAKE_DIR#boss"

  success "Nix / Home Manager done."
fi

# ── 2. apt (system packages) ─────────────────────────────────────────────────
step "2/7  apt (system packages)"

if ! command -v apt-get &>/dev/null; then
  warn "apt-get not found — not an apt-based system?"
  RESULTS["apt"]="skipped (no apt)"
else
  run_step "apt update + upgrade" bash -c "
    sudo apt-get update -qq && \
    sudo apt-get upgrade -y --with-new-pkgs && \
    sudo apt-get autoremove -y
  "
  success "apt done."
fi

# ── 3. Homebrew ───────────────────────────────────────────────────────────────
step "3/7  Homebrew"

if ! command -v brew &>/dev/null; then
  skipped "brew not found — skipping."
  RESULTS["Homebrew"]="skipped (not installed)"
else
  # brew update: fetches latest formula definitions
  # brew upgrade: upgrades installed formulae to latest versions
  run_step "brew update + upgrade" bash -c "brew update && brew upgrade"
  success "Homebrew done."
fi

# ── 4. npm global AI CLIs ─────────────────────────────────────────────────────
step "4/7  npm global packages (AI CLIs)"

if ! command -v npm &>/dev/null; then
  skipped "npm not found — skipping."
  RESULTS["npm globals"]="skipped (no npm)"
else
  # These are the AI CLI tools installed to ~/.npm-global in shell.nix.
  # npm update -g upgrades ALL packages in the prefix to their latest versions.
  # This is the equivalent of the old ansible `npm install -g <pkg>@latest` loop.
  #
  # Note: yt-dlp was previously updated to a nightly build via pipx.
  # It is now installed via Nix (pkgs.yt-dlp) and updated with the flake above.
  # If you specifically need the nightly build, uncomment the yt-dlp block at
  # the bottom of this file.
  info "Updating AI CLI tools in $NPM_CONFIG_PREFIX ..."
  run_step "npm update -g" \
    npm update --global --prefix "$NPM_CONFIG_PREFIX"
  success "npm global packages done."
fi

# ── 5. Flatpak ────────────────────────────────────────────────────────────────
step "5/7  Flatpak"

if ! command -v flatpak &>/dev/null; then
  skipped "flatpak not found — skipping."
  RESULTS["Flatpak"]="skipped (not installed)"
else
  # Update user-installed Flatpak apps. --noninteractive avoids prompts in cron.
  run_step "flatpak update" \
    flatpak update --user --noninteractive --assumeyes

  # Snapshot installed Flatpak app IDs to flatpak.md, grouped by remote.
  FLATPAK_LIST_FILE="$SCRIPT_DIR/flatpak.md"
  if ! $DRY_RUN; then
    {
      # Collect all remotes that have at least one app installed; flathub handled first.
      mapfile -t OTHER_REMOTES < <(
        flatpak list --app --columns=origin | sort -u | grep -v '^flathub$'
      )

      # Flathub section first (primary remote).
      printf '## Flathub\n\n'
      flatpak list --app --columns=application,origin \
        | awk -F'\t' '$2=="flathub"{print $1}' | sort -u

      # Remaining remotes in alphabetical order.
      for remote in "${OTHER_REMOTES[@]}"; do
        case "$remote" in
          flathub-beta)  title="Flathub Beta" ;;
          GeForceNOW)    title="GeForce NOW" ;;
          *)             title="$remote" ;;
        esac
        printf '\n## %s\n\n' "$title"
        flatpak list --app --columns=application,origin \
          | awk -F'\t' -v r="$remote" '$2==r{print $1}' | sort -u
      done
    } > "$FLATPAK_LIST_FILE"
    info "Updated flatpak.md ($(grep -c '^[a-zA-Z]' "$FLATPAK_LIST_FILE") apps)."
  else
    echo -e "  ${DIM}[dry-run] Would write flatpak.md grouped by remote${NC}"
  fi

  success "Flatpak done."
fi

# ── 6. pipx ───────────────────────────────────────────────────────────────────
step "6/7  pipx"

if ! command -v pipx &>/dev/null; then
  skipped "pipx not found — skipping."
  RESULTS["pipx"]="skipped (not installed)"
else
  # Upgrade all pipx-managed packages. Most tools have been migrated to Nix
  # (yt-dlp, poetry, uv, key-mon), but any remaining pipx installs are upgraded.
  run_step "pipx upgrade-all" pipx upgrade-all
  success "pipx done."
fi

# ── 7. Distrobox containers ───────────────────────────────────────────────────
step "7/7  Distrobox containers"

if ! command -v distrobox &>/dev/null; then
  skipped "distrobox not found — skipping."
  RESULTS["Distrobox"]="skipped (not in PATH)"
elif ! $UPDATE_DISTROBOX; then
  skipped "Skipping distrobox updates (--no-distrobox)."
  RESULTS["Distrobox"]="skipped (--no-distrobox)"
else
  # `distrobox upgrade` runs the container's native package manager upgrade
  # (apt upgrade inside 'dev', dnf upgrade inside 'media').
  # --all upgrades every container; skips containers that aren't running yet.
  run_step "distrobox upgrade --all" \
    distrobox upgrade --all
  success "Distrobox containers done."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
ELAPSED=$(( $(date +%s) - START_TIME ))
MINUTES=$(( ELAPSED / 60 ))
SECONDS=$(( ELAPSED % 60 ))

echo ""
echo -e "${BOLD}━━━ Update Summary ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "  %-30s %s\n" "Step" "Result"
printf "  %-30s %s\n" "----" "------"
for key in "Nix flake update" "home-manager switch" "apt" "Homebrew" \
           "npm globals" "Flatpak" "pipx" "Distrobox"; do
  result="${RESULTS[$key]:-—}"
  if [[ "$result" == ✓* ]]; then
    echo -e "  $(printf '%-30s' "$key") ${GREEN}${result}${NC}"
  elif [[ "$result" == ✗* ]]; then
    echo -e "  $(printf '%-30s' "$key") ${RED}${result}${NC}"
  else
    echo -e "  $(printf '%-30s' "$key") ${DIM}${result}${NC}"
  fi
done
echo ""
echo -e "  Total time: ${MINUTES}m ${SECONDS}s"
echo ""

# Warn if any step failed
FAILED=()
for key in "${!RESULTS[@]}"; do
  [[ "${RESULTS[$key]}" == ✗* ]] && FAILED+=("$key")
done
if [[ ${#FAILED[@]} -gt 0 ]]; then
  warn "Some steps failed: ${FAILED[*]}"
  warn "Check the output above for details."
fi

success "All updates complete."

# ── Home Manager News ─────────────────────────────────────────────────────────
HM_NEWS_FILE="$SCRIPT_DIR/docs/research/home-manager-news.md"

echo ""
echo -e "${CYAN}${BOLD}━━━ Home Manager News ━━━${NC}"
info "Checking home-manager news (output suppressed)..."

HM_NEWS_OUTPUT=$(home-manager news --flake "$NIX_FLAKE_DIR#boss" 2>&1 | grep -v 'has uncommitted changes') || true

if [[ -z "$HM_NEWS_OUTPUT" ]]; then
  info "No home-manager news output."
else
  # Filter to [unread] entries only
  HM_NEWS_UNREAD=$(awk '
    /^\* / {
      if (block != "" && unread) printf "%s", block
      block = $0 "\n"; unread = ($0 ~ /\[unread\]/); next
    }
    { block = block $0 "\n" }
    END { if (block != "" && unread) printf "%s", block }
  ' <<< "$HM_NEWS_OUTPUT")

  # Extract existing News section content for comparison
  EXISTING_NEWS=""
  if [[ -f "$HM_NEWS_FILE" ]]; then
    EXISTING_NEWS=$(sed -n '/^## News$/,$ { /^## News$/d; p }' "$HM_NEWS_FILE")
    # Trim leading blank line added by the section header
    EXISTING_NEWS="${EXISTING_NEWS#$'\n'}"
  fi

  if [[ "$HM_NEWS_UNREAD" == "$EXISTING_NEWS" ]]; then
    info "No unread home-manager news since last update."
  else
    WRITE_NEWS=false
    if $DRY_RUN; then
      echo -e "  ${DIM}[dry-run] Would prompt to update $HM_NEWS_FILE${NC}"
    elif [[ -t 0 ]]; then
      echo ""
      if [[ -n "$HM_NEWS_UNREAD" ]]; then
        echo -e "${YELLOW}New unread home-manager news is available.${NC}"
      else
        echo -e "${YELLOW}All home-manager news has been read — clearing news file.${NC}"
      fi
      printf "  Overwrite docs/home-manager-news.md? [Y/n] "
      read -r ANSWER </dev/tty || ANSWER="N"
      ANSWER="${ANSWER:-Y}"
      [[ "$ANSWER" =~ ^[Yy]$ ]] && WRITE_NEWS=true
    else
      info "Non-interactive session — skipping home-manager-news.md update."
    fi

    if $WRITE_NEWS; then
      mkdir -p "$(dirname "$HM_NEWS_FILE")"
      {
        printf '## Meta\n\n'
        printf 'This file is maintained by `update.sh` and updated during system updates.\n\n'
        printf '**Structure:**\n'
        printf -- '- **Meta** (this section): Documents the structure and formatting of this file.\n'
        printf -- '- **News**: Unread entries only — `[read]` entries are excluded.\n\n'
        printf '**Formatting rules for the News section:**\n'
        printf -- '- Content is filtered output of `home-manager news` — do not hand-edit it.\n'
        printf -- '- Each news entry starts with a `* DATE [unread]` header.\n'
        printf -- '- Entries are separated by blank lines.\n\n'
        printf '**Update behaviour:** `update.sh` compares new unread news against the stored\n'
        printf 'News section and prompts before overwriting (Y/n, default Y). Skipped in\n'
        printf 'non-interactive (cron) sessions.\n\n'
        printf 'Last updated: %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf '## News\n\n'
        [[ -n "$HM_NEWS_UNREAD" ]] && printf '%s\n' "$HM_NEWS_UNREAD"
      } > "$HM_NEWS_FILE"
      success "docs/home-manager-news.md updated."
    fi
  fi
fi

# Exit with failure if any step failed
[[ ${#FAILED[@]} -gt 0 ]] && exit 1

# ─────────────────────────────────────────────────────────────────────────────
# Optional: yt-dlp nightly
# ─────────────────────────────────────────────────────────────────────────────
# The Nix-managed yt-dlp (pkgs.yt-dlp) is updated whenever you run
# `nix flake update` above — nixpkgs-unstable usually picks up new yt-dlp
# releases within a day or two, which is sufficient for most use cases.
#
# If you need the absolute latest nightly build (e.g. a site broke today and
# the fix is in HEAD), uncomment and adapt the block below:
#
# step "yt-dlp nightly (optional)"
# if command -v pip3 &>/dev/null; then
#   run_step "yt-dlp nightly" \
#     pip3 install --user --upgrade \
#       "https://github.com/yt-dlp/yt-dlp/archive/master.tar.gz#egg=yt-dlp"
#   # Note: this installs a ~/.local/bin/yt-dlp that shadows the Nix one.
#   # Remove with: pip3 uninstall yt-dlp && hash -r
# fi
