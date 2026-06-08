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
#   ./update.sh                    # Full update (all managers)
#   ./update.sh --no-nix           # Skip Nix flake update (faster, uses locked versions)
#   ./update.sh --no-distrobox     # Skip container OS upgrades
#   ./update.sh --no-stable-check  # Skip the nixpkgs stable-release upgrade check
#   ./update.sh --no-gc            # Skip Nix store garbage collection
#   ./update.sh --dry-run          # Print what would run without executing
#
# Cron example (daily at 10:00):
#   0 10 * * * /home/boss/Projects/installs/update.sh >> /tmp/update.log 2>&1

set -euo pipefail

# ── Options ───────────────────────────────────────────────────────────────────
UPDATE_NIX=true
UPDATE_DISTROBOX=true
CHECK_STABLE=true
GC_NIX=true
DRY_RUN=false

# Minimum age (in days) of the upstream commit each pinned flake input is
# advanced to. Older commits are reliably covered by Hydra's binary cache,
# so home-manager switch downloads pre-built artifacts rather than compiling.
# Override via env: PIN_AGE_DAYS=21 ./update.sh
PIN_AGE_DAYS="${PIN_AGE_DAYS:-14}"

for arg in "$@"; do
  case "$arg" in
    --no-nix)           UPDATE_NIX=false ;;
    --no-distrobox)     UPDATE_DISTROBOX=false ;;
    --no-stable-check)  CHECK_STABLE=false ;;
    --no-gc)            GC_NIX=false ;;
    --dry-run)          DRY_RUN=true ;;
    --help|-h)
      grep '^#' "$0" | head -21 | sed 's/^# \?//'
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

# ── Helpers ───────────────────────────────────────────────────────────────────

# Query GitHub for the highest nixos-XX.YY branch name (e.g. "nixos-25.11").
# Returns empty string if gh is unavailable or the query fails.
_latest_stable_release() {
  gh api 'repos/NixOS/nixpkgs/branches?per_page=100' --paginate \
    --jq '.[].name' 2>/dev/null \
    | grep -E '^nixos-[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -1
}

# Find the newest commit on <owner>/<repo>@<branch> that is at least <days>
# old. Echoes the 40-char SHA on stdout; empty + non-zero on failure.
# Uses `gh api --paginate` walking commits from newest backwards.
_latest_commit_at_least_n_days_old() {
  local owner="$1" repo="$2" branch="$3" days="$4"
  local cutoff
  cutoff=$(date -u -d "${days} days ago" +%s) || return 1

  gh api "repos/${owner}/${repo}/commits?sha=${branch}&per_page=100" --paginate \
    --jq '.[] | "\(.sha) \(.commit.committer.date)"' 2>/dev/null \
    | while read -r sha date; do
        local ts
        ts=$(date -u -d "$date" +%s 2>/dev/null) || continue
        if (( ts <= cutoff )); then
          echo "$sha"
          return 0
        fi
      done
  return 1
}

# Read the upstream branch name recorded in the `# channel: <name>` comment
# immediately preceding the given input's `.url = ...` line in flake.nix.
# Args: <flake.nix path> <input name, e.g. nixpkgs>
_channel_for_input() {
  local flake="$1" input="$2"
  awk -v key="$input" '
    # Track the most recent `# channel: <name>` comment seen.
    /^[[:space:]]*#[[:space:]]*channel:[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*#[[:space:]]*channel:[[:space:]]*/, "", line)
      ch = line
      next
    }
    # Single-line form:  <key>.url = "github:...";
    $0 ~ "^[[:space:]]*" key "\\.url[[:space:]]*=" { print ch; exit }
    # Block form:        <key> = {  ...  url = "github:...";  ... };
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=[[:space:]]*\\{" { in_block = 1; next }
    in_block && /^[[:space:]]*url[[:space:]]*=/ { print ch; exit }
    in_block && /^[[:space:]]*\};/ { in_block = 0 }
  ' "$flake"
}

# Replace the SHA inside the URL of the given input in flake.nix. Idempotent.
# Args: <flake.nix path> <input name> <owner/repo path> <new sha>
_pin_input_sha() {
  local flake="$1" input="$2" repo_path="$3" sha="$4"
  # Match: "github:<repo_path>/<old-sha-or-branch>"   on the input's url line.
  # Anchor by `<input>.url = "github:<repo_path>/...` to avoid touching others.
  python3 - "$flake" "$input" "$repo_path" "$sha" <<'PY'
import re, sys
flake, name, repo, sha = sys.argv[1:5]
with open(flake) as f:
    text = f.read()
# Match either `<name>.url = "github:repo/X"` or `<name> = { ... url = "github:repo/X" ... }`.
pat = re.compile(
    r'(\b' + re.escape(name) + r'(?:\s*=\s*\{[^}]*?)?\s*\.?url\s*=\s*")github:'
    + re.escape(repo) + r'/[^"]+(")',
    re.DOTALL,
)
new, n = pat.subn(r'\1github:' + repo + '/' + sha + r'\2', text, count=1)
if n != 1:
    sys.stderr.write(f"_pin_input_sha: failed to match {name} -> github:{repo}/...\n")
    sys.exit(2)
with open(flake, "w") as f:
    f.write(new)
PY
}

# Read the currently-pinned SHA out of the input's URL in flake.nix.
# Args: <flake.nix path> <input name> <owner/repo path>
_current_input_sha() {
  local flake="$1" input="$2" repo_path="$3"
  python3 - "$flake" "$input" "$repo_path" <<'PY'
import re, sys
flake, name, repo = sys.argv[1:4]
with open(flake) as f:
    text = f.read()
pat = re.compile(
    r'\b' + re.escape(name) + r'(?:\s*=\s*\{[^}]*?)?\s*\.?url\s*=\s*"github:'
    + re.escape(repo) + r'/([^"]+)"',
    re.DOTALL,
)
m = pat.search(text)
print(m.group(1) if m else "")
PY
}

# Echo the Nix-store path of the SUID sandbox helper that the Nix chromium
# wrapper currently points at, e.g.
#   /nix/store/…-ungoogled-chromium-148.0.7778.178-sandbox/bin/__chromium-suid-sandbox
# The path encodes the chromium version, so a change across a home-manager
# switch means chromium was bumped. Empty (and rc 0) if chromium isn't present.
# See scripts/chromium-suid-sandbox.sh / custom-installers.yml for why the
# helper must be reinstalled when this changes.
_chromium_helper_path() {
  local wrapper="$HOME/.nix-profile/bin/chromium"
  [[ -x "$wrapper" ]] || return 0
  grep -oE '/nix/store/[^"]*-sandbox/bin/__chromium-suid-sandbox' "$wrapper" 2>/dev/null \
    | tail -1 || true
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
step "1/9  Nix + Home Manager"

if ! command -v nix &>/dev/null; then
  warn "nix not found — skipping Nix updates. Run ./bootstrap.sh first."
  RESULTS["Nix"]="skipped (not installed)"
else
  if $UPDATE_NIX; then
    # ── Stable-release upgrade check ──────────────────────────────────────────
    # If the config is pinned to a named stable release (nixos-XX.YY), check
    # whether a newer stable branch has shipped. If so, offer to update both
    # nixpkgs.url and home-manager.url in flake.nix before regenerating the lock.
    # llm-agents.nix is intentionally left untouched (no release versioning).
    if $CHECK_STABLE && command -v gh &>/dev/null; then
      # Read the upstream channel name from the structured `# channel:`
      # comment that precedes the nixpkgs input in flake.nix. The URL itself
      # holds a 40-char SHA (the age-pin), so we can't recover the channel
      # from there.
      current_channel=$(_channel_for_input "$NIX_FLAKE_DIR/flake.nix" nixpkgs)

      if [[ "$current_channel" =~ ^nixos-[0-9]+\.[0-9]+$ ]]; then
        info "Checking for newer nixpkgs stable release (current: $current_channel)..."
        latest_stable=$(_latest_stable_release)

        if [[ -z "$latest_stable" ]]; then
          warn "Could not fetch latest stable release from GitHub — skipping check."
          RESULTS["nixpkgs stable upgrade"]="skipped (fetch failed)"
        elif [[ "$latest_stable" == "$current_channel" ]]; then
          info "nixpkgs is already on the latest stable ($current_channel)."
          RESULTS["nixpkgs stable upgrade"]="✓ up to date"
        else
          echo ""
          warn "New stable release available: ${current_channel} → ${latest_stable}"
          DO_UPGRADE=false
          if $DRY_RUN; then
            echo -e "  ${DIM}[dry-run] Would prompt to upgrade flake.nix to $latest_stable${NC}"
            RESULTS["nixpkgs stable upgrade"]="skipped (dry-run)"
          elif [[ -t 1 ]]; then
            printf "  Upgrade flake.nix to %s? [Y/n] " "$latest_stable"
            read -r STABLE_ANSWER </dev/tty || STABLE_ANSWER="N"
            STABLE_ANSWER="${STABLE_ANSWER:-Y}"
            [[ "$STABLE_ANSWER" =~ ^[Yy]$ ]] && DO_UPGRADE=true
          else
            info "Non-interactive session — skipping stable upgrade."
            info "Run update.sh interactively to upgrade to $latest_stable."
            RESULTS["nixpkgs stable upgrade"]="skipped (non-interactive)"
          fi

          if $DO_UPGRADE; then
            # Rewrite the `# channel:` comments only — the URLs hold SHAs and
            # will be re-pinned to a ≥${PIN_AGE_DAYS}-day-old commit on the
            # NEW channel by the age-pin step below in this same run.
            sed -i \
              -e "s|# channel: ${current_channel}\b|# channel: ${latest_stable}|" \
              "$NIX_FLAKE_DIR/flake.nix"
            # Matching home-manager release branch (nixos-25.11 → release-25.11).
            hm_new="release-${latest_stable#nixos-}"
            hm_old="release-${current_channel#nixos-}"
            sed -i "s|# channel: ${hm_old}\b|# channel: ${hm_new}|" \
              "$NIX_FLAKE_DIR/flake.nix"
            success "flake.nix channel updated: $current_channel → $latest_stable"
            RESULTS["nixpkgs stable upgrade"]="✓ ${current_channel}→${latest_stable}"
          fi
        fi

      elif [[ "$current_channel" =~ ^nixpkgs-unstable$|^nixos-unstable$ ]]; then
        latest_stable=$(_latest_stable_release)
        if [[ -n "$latest_stable" ]]; then
          info "On unstable. Latest stable release is ${latest_stable} (FYI — no action taken)."
        fi
        RESULTS["nixpkgs stable upgrade"]="— (on unstable)"
      fi
    fi

    # ── Age-pin nixpkgs / home-manager to a ≥PIN_AGE_DAYS-old commit ────────
    # Rewrite the SHAs embedded in flake.nix's input URLs to the newest
    # upstream commit on each tracked branch that is at least PIN_AGE_DAYS
    # old. By the time a commit is that old, Hydra has fully populated its
    # binary cache for it, so home-manager switch downloads pre-built store
    # paths instead of compiling from source. Subsequent same-day `hms` runs
    # then reuse those cached paths from flake.lock without further work.
    #
    # The `nix flake update` afterwards reads the new SHAs out of flake.nix
    # and writes them into flake.lock (and refreshes unpinned inputs like
    # llm-agents to their HEAD, which has its own daily binary cache).
    if command -v gh &>/dev/null; then
      info "Age-pinning flake inputs to ≥${PIN_AGE_DAYS}-day-old commits..."
      # Inputs to age-pin: <input-name> <github owner/repo>
      pin_specs=(
        "nixpkgs NixOS/nixpkgs"
        "nixpkgs-unstable NixOS/nixpkgs"
        "home-manager nix-community/home-manager"
      )
      for spec in "${pin_specs[@]}"; do
        read -r in_name repo_path <<< "$spec"
        owner="${repo_path%%/*}"
        repo="${repo_path##*/}"
        branch=$(_channel_for_input "$NIX_FLAKE_DIR/flake.nix" "$in_name")
        if [[ -z "$branch" ]]; then
          warn "  ${in_name}: no '# channel:' comment found in flake.nix — skipping age-pin."
          RESULTS["age-pin ${in_name}"]="skipped (no channel comment)"
          continue
        fi
        old_sha=$(_current_input_sha "$NIX_FLAKE_DIR/flake.nix" "$in_name" "$repo_path")
        new_sha=$(_latest_commit_at_least_n_days_old "$owner" "$repo" "$branch" "$PIN_AGE_DAYS") || true
        if [[ -z "$new_sha" ]]; then
          warn "  ${in_name}: could not find a ≥${PIN_AGE_DAYS}d-old commit on ${branch}."
          RESULTS["age-pin ${in_name}"]="✗ fetch failed"
          continue
        fi
        if [[ "$new_sha" == "$old_sha" ]]; then
          info "  ${in_name} (${branch}): up to date (${new_sha:0:7})."
          RESULTS["age-pin ${in_name}"]="✓ up to date"
          continue
        fi
        if $DRY_RUN; then
          echo -e "  ${DIM}[dry-run] would pin ${in_name}: ${old_sha:0:7} → ${new_sha:0:7}${NC}"
          RESULTS["age-pin ${in_name}"]="skipped (dry-run)"
          continue
        fi
        _pin_input_sha "$NIX_FLAKE_DIR/flake.nix" "$in_name" "$repo_path" "$new_sha"
        success "  ${in_name} (${branch}): ${old_sha:0:7} → ${new_sha:0:7}"
        RESULTS["age-pin ${in_name}"]="✓ ${old_sha:0:7}→${new_sha:0:7}"
      done
    else
      warn "gh not available — skipping age-pin step. flake.lock will not advance."
      RESULTS["age-pin nixpkgs"]="skipped (no gh)"
    fi

    # Resolve the (possibly updated) flake.nix URLs into flake.lock. Also
    # refreshes unpinned inputs (llm-agents, tuxManager, ie-r) to their HEAD.
    info "Updating flake.lock..."
    run_step "Nix flake update" nix flake update --flake "$NIX_FLAKE_DIR"
  else
    info "Skipping flake.lock update (--no-nix). Using locked package versions."
    RESULTS["Nix flake update"]="skipped (--no-nix)"
  fi

  # Apply the (possibly updated) Home Manager configuration.
  # This installs new packages, updates changed ones, and runs activation scripts
  # (including distrobox container creation and npm AI CLI installation).
  # --no-write-lock-file: only update.sh's flake update step is allowed to
  # advance flake.lock; if home-manager switch wanted to write the lock here
  # it would mean an input failed to resolve, which is a real error.
  info "Applying Home Manager configuration..."
  # Snapshot chromium's helper path before switching so we can tell afterwards
  # whether the switch bumped chromium (see the restart block below).
  CHROMIUM_HELPER_BEFORE="$(_chromium_helper_path)"
  run_step "home-manager switch" \
    home-manager switch --flake "$NIX_FLAKE_DIR#boss" --no-write-lock-file

  # If the switch bumped Chromium, the version-specific SUID sandbox helper
  # copied to /run/wrappers/bin is now stale and Chromium can refuse to launch
  # until it's refreshed. Restart the installer service to reinstall a matching
  # setuid helper — but only when the helper path actually changed (it encodes
  # the chromium version), so unchanged installs don't touch sudo.
  if [[ -f /etc/systemd/system/chromium-suid-sandbox.service ]]; then
    CHROMIUM_HELPER_AFTER="$(_chromium_helper_path)"
    if [[ -n "$CHROMIUM_HELPER_AFTER" \
          && "$CHROMIUM_HELPER_AFTER" != "$CHROMIUM_HELPER_BEFORE" ]]; then
      info "Chromium changed — refreshing SUID sandbox helper (needs sudo)."
      run_step "chromium-suid-sandbox restart" \
        sudo systemctl restart chromium-suid-sandbox.service
    else
      skipped "Chromium unchanged — SUID sandbox helper still current."
      RESULTS["chromium-suid-sandbox restart"]="✓ unchanged"
    fi
  fi

  success "Nix / Home Manager done."
fi

# ── 2. apt (system packages) ─────────────────────────────────────────────────
step "2/9  apt (system packages)"

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
step "3/9  Homebrew"

if ! command -v brew &>/dev/null; then
  skipped "brew not found — skipping."
  RESULTS["Homebrew"]="skipped (not installed)"
else
  # brew update: fetches latest formula definitions
  # brew upgrade: upgrades installed formulae to latest versions
  run_step "brew update + upgrade" bash -c "brew update && brew upgrade"

  # Sync declared state: install new entries, remove unlisted ones.
  run_step "brew bundle sync" brew bundle install --cleanup --file="$SCRIPT_DIR/Brewfile"

  success "Homebrew done."
fi

# ── 4. npm global AI CLIs ─────────────────────────────────────────────────────
step "4/9  npm global packages (AI CLIs)"

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
step "5/9  Flatpak"

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
step "6/9  pipx"

if ! command -v pipx &>/dev/null; then
  skipped "pipx not found — skipping."
  RESULTS["pipx"]="skipped (not installed)"
else
  # Upgrade all pipx-managed packages. Most tools have been migrated to Nix
  # (yt-dlp, poetry, uv, key-mon), but any remaining pipx installs are upgraded.
  # If venvs reference a Python that no longer exists (e.g. after a system
  # Python bump), reinstall-all rebuilds them against the current interpreter.
  pipx_upgrade_all() {
    if pipx upgrade-all; then
      return 0
    fi
    if pipx list 2>&1 | grep -q 'invalid interpreter'; then
      warn "pipx venvs reference a missing Python — running reinstall-all."
      pipx reinstall-all && pipx upgrade-all
    else
      return 1
    fi
  }
  run_step "pipx upgrade-all" pipx_upgrade_all
  success "pipx done."
fi

# ── 7. AppMan (AM) — AppImages ────────────────────────────────────────────────
step "7/9  AppMan (AM) — AppImages"

if ! command -v appman &>/dev/null; then
  skipped "appman not found — skipping."
  RESULTS["AppMan"]="skipped (not installed)"
else
  # `appman -u` self-updates AM and upgrades every managed AppImage. Runs
  # non-interactively (no TTY prompts), matching the rest of update.sh.
  run_step "appman update" appman -u
  success "AppMan done."
fi

# ── 8. Distrobox containers ───────────────────────────────────────────────────
step "8/9  Distrobox containers"

if ! command -v distrobox &>/dev/null; then
  skipped "distrobox not found — skipping."
  RESULTS["Distrobox"]="skipped (not in PATH)"
elif ! $UPDATE_DISTROBOX; then
  skipped "Skipping distrobox updates (--no-distrobox)."
  RESULTS["Distrobox"]="skipped (--no-distrobox)"
else
  # Upgrade containers one-by-one (instead of `distrobox upgrade --all`) so the
  # user gets per-container progress feedback — `--all` can sit silently for
  # many minutes while apt/dnf churns inside a single container.
  # `distrobox list` shells out to podman; if a previous run left a wedged
  # podman process holding the storage lock, this call hangs forever with no
  # output. Cap it at 30s so the step fails loudly instead of freezing the
  # whole script.
  DBOX_LIST_OUTPUT=$(timeout 30 distrobox list --no-color 2>/dev/null)
  if [[ $? -eq 124 ]]; then
    warn "distrobox list timed out — podman may be wedged. Try: pgrep -fa podman ; then kill stuck PIDs and re-run."
    RESULTS["Distrobox"]="✗ list timed out (podman wedged?)"
    DBOX_CONTAINERS=()
  else
    mapfile -t DBOX_CONTAINERS < <(printf '%s\n' "$DBOX_LIST_OUTPUT" \
      | awk -F'|' 'NR>1 {gsub(/^ +| +$/, "", $2); if ($2 != "") print $2}')
  fi

  if [[ ${#DBOX_CONTAINERS[@]} -eq 0 ]] && [[ -z "${RESULTS["Distrobox"]:-}" ]]; then
    skipped "No distrobox containers found."
    RESULTS["Distrobox"]="skipped (none found)"
  elif [[ ${#DBOX_CONTAINERS[@]} -eq 0 ]]; then
    : # already set by timeout branch above
  else
    info "Found ${#DBOX_CONTAINERS[@]} container(s): ${DBOX_CONTAINERS[*]}"
    DBOX_FAILED=()
    DBOX_START=$(date +%s)
    for i in "${!DBOX_CONTAINERS[@]}"; do
      c="${DBOX_CONTAINERS[$i]}"
      info "[$((i+1))/${#DBOX_CONTAINERS[@]}] Upgrading '$c' (apt/dnf inside container — may take several minutes)..."
      c_start=$(date +%s)
      # stdbuf -oL -eL: force line-buffered output so progress streams instead
      # of hanging in pipe buffers. </dev/null: refuse interactive prompts so
      # apt/dnf fails fast instead of waiting forever on stdin. timeout 45m:
      # bound runaway upgrades so the script doesn't appear to freeze.
      if timeout 45m stdbuf -oL -eL distrobox upgrade "$c" </dev/null 2>&1; then
        c_elapsed=$(( $(date +%s) - c_start ))
        success "  '$c' upgraded in ${c_elapsed}s."
      else
        rc=$?
        c_elapsed=$(( $(date +%s) - c_start ))
        if [[ $rc -eq 124 ]]; then
          warn "  '$c' upgrade timed out after ${c_elapsed}s — continuing."
        else
          warn "  '$c' upgrade failed (rc=$rc) after ${c_elapsed}s — continuing."
        fi
        DBOX_FAILED+=("$c")
      fi
    done
    DBOX_ELAPSED=$(( $(date +%s) - DBOX_START ))
    if [[ ${#DBOX_FAILED[@]} -eq 0 ]]; then
      RESULTS["Distrobox"]="✓ ${DBOX_ELAPSED}s"
      success "Distrobox containers done (${DBOX_ELAPSED}s total)."
    else
      RESULTS["Distrobox"]="✗ failed: ${DBOX_FAILED[*]}"
      warn "Distrobox: ${#DBOX_FAILED[@]} container(s) failed: ${DBOX_FAILED[*]}"
    fi
  fi
fi

# ── 9. Nix garbage collection ────────────────────────────────────────────────
step "9/9  Nix garbage collection"

if ! command -v nix-collect-garbage &>/dev/null; then
  skipped "nix-collect-garbage not found — skipping."
  RESULTS["Nix GC"]="skipped (not installed)"
elif ! $GC_NIX; then
  skipped "Skipping Nix GC (--no-gc)."
  RESULTS["Nix GC"]="skipped (--no-gc)"
else
  BEFORE=$(df --output=avail /nix 2>/dev/null | tail -1 || echo 0)
  run_step "Nix GC" nix-collect-garbage --delete-older-than 30d
  AFTER=$(df --output=avail /nix 2>/dev/null | tail -1 || echo 0)
  FREED=$(( (AFTER - BEFORE) / 1024 ))
  [[ $FREED -gt 0 ]] && info "Freed ~${FREED} MiB from /nix."
  success "Nix garbage collection done."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
ELAPSED=$(( $(date +%s) - START_TIME ))
MINUTES=$(( ELAPSED / 60 ))
SECONDS=$(( ELAPSED % 60 ))

echo ""
echo -e "${BOLD}━━━ Update Summary ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "  %-30s %s\n" "Step" "Result"
printf "  %-30s %s\n" "----" "------"
for key in "nixpkgs stable upgrade" \
           "age-pin nixpkgs" "age-pin nixpkgs-unstable" "age-pin home-manager" \
           "Nix flake update" "home-manager switch" "chromium-suid-sandbox restart" \
           "apt" "Homebrew" "brew install new" "npm globals" "Flatpak" "pipx" "AppMan" "appman update" "Distrobox" "Nix GC"; do
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
