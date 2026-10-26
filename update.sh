#!/usr/bin/env bash
# update.sh — Update all packages across every package manager.
#
# Replaces the daily `ansible-playbook ansible.yml` run that previously handled
# package upgrades. Covers:
#
#   1. Nix / Home Manager  — flake.lock update + home-manager switch
#   2. apt                 — system packages (docker, KDE libs, etc.)
#   3. Homebrew            — remaining brew packages not in Nix
#   4. npm globals         — CLIs declared in npm-globals.txt (~/.npm-global)
#   5. Flatpak             — user Flatpak apps
#   6. uv tools            — Python CLI tools declared in uv-tools.txt
#   7. Distrobox           — OS packages inside containers
#
# Usage:
#   ./update.sh                    # Full update (all managers)
#   ./update.sh --no-nix           # Skip Nix flake update (faster, uses locked versions)
#   ./update.sh --no-distrobox     # Skip container OS upgrades
#   ./update.sh --no-stable-check  # Skip the nixpkgs stable-release upgrade check
#   ./update.sh --dry-run          # Print what would run without executing
#
# Runs unattended daily via the update-all systemd user timer
# (nix/modules/services.nix); root steps are NOPASSWD via ansible.yml.
#   systemctl --user start update-all.service   # trigger a background run now
#
# Every run is logged to ~/.local/state/update-all/update.log (5 MB cap, then
# rotated to update.log.1).

# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Raise the soft open-files limit to the hard limit. Shells spawned outside the
# systemd user session (e.g. a detached `tmux new-session -d`) inherit the
# default soft limit of 1024, which Nix flake evaluation (lazy-trees + dirty
# git tree) can exhaust → "error: opening file ...: Too many open files".
ulimit -Sn "$(ulimit -Hn)" 2>/dev/null || true

# ── Options ───────────────────────────────────────────────────────────────────
UPDATE_NIX=true
UPDATE_DISTROBOX=true
CHECK_STABLE=true
DRY_RUN=false

# Minimum age (in days) of the upstream commit each pinned flake input is
# advanced to. For nixpkgs this is the age of the channel *release* (when Hydra
# published it), not the commit date. Older releases are reliably covered by
# Hydra's binary cache, so home-manager switch downloads pre-built artifacts
# rather than compiling.
# Override via env: PIN_AGE_DAYS=21 ./update.sh
PIN_AGE_DAYS="${PIN_AGE_DAYS:-14}"

# Same idea, but for llm-agents.nix (claude/codex/opencode/... CLIs). numtide
# rebuilds and republishes its binary cache (cache.numtide.com) daily, so a
# 1-day floor is enough to reliably hit the cache without going stale for
# weeks like nixpkgs. Override via env: PIN_AGE_DAYS_LLM_AGENTS=2 ./update.sh
PIN_AGE_DAYS_LLM_AGENTS="${PIN_AGE_DAYS_LLM_AGENTS:-1}"

# Supply-chain cooldown for the other third-party inputs (sops-nix, delta,
# tuxManager, ie-r, context7): no cache reason to wait, but a compromised or
# broken upstream commit gets this long to be noticed before we adopt it.
# orca is shorter so its skills don't lag the (freely updating) Orca app CLI.
# Override via env: PIN_AGE_DAYS_SOURCE=14 PIN_AGE_DAYS_ORCA=1 ./update.sh
PIN_AGE_DAYS_SOURCE="${PIN_AGE_DAYS_SOURCE:-7}"
PIN_AGE_DAYS_ORCA="${PIN_AGE_DAYS_ORCA:-2}"

# Inputs whose source feeds instructions straight into Claude (skills). When
# they move, print a compare link so the diff can be skimmed.
REVIEW_INPUTS=" orca context7 rea "

for arg in "$@"; do
  case "$arg" in
    --no-nix)           UPDATE_NIX=false ;;
    --no-distrobox)     UPDATE_DISTROBOX=false ;;
    --no-stable-check)  CHECK_STABLE=false ;;
    --dry-run)          DRY_RUN=true ;;
    --help|-h)
      grep '^#' "$0" | sed -n '2,21p' | sed 's/^# \?//'
      exit 0
      ;;
  esac
done

# ── Run log ───────────────────────────────────────────────────────────────────
# Every run's full output is appended (ANSI colours and \r progress redraws
# stripped) to $UPDATE_LOG for later review. Size cap: once the log exceeds
# UPDATE_LOG_MAX_BYTES it's rotated to .1 (previous .1 dropped), so at most
# ~2× the cap is kept on disk.
UPDATE_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/update-all/update.log"
UPDATE_LOG_MAX_BYTES=$(( 5 * 1024 * 1024 ))

# stdin: raw terminal output → stdout: plain text.
_clean_log() {
  sed -u -E \
    -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' \
    -e 's/\x1b\][^\x07]*\x07//g' \
    -e 's/\r+$//' \
    -e 's/.*\r//'
}

_rotate_log() {
  mkdir -p "$(dirname "$UPDATE_LOG")"
  if [[ -f "$UPDATE_LOG" ]] && (( $(stat -c %s "$UPDATE_LOG") > UPDATE_LOG_MAX_BYTES )); then
    mv -f "$UPDATE_LOG" "$UPDATE_LOG.1"
  fi
}

_log_hint() { echo -e "\n\033[0;34m[INFO]\033[0m  Full log: $UPDATE_LOG"; }

if [[ -z "${UPDATE_SH_LOGGING:-}" ]]; then
  export UPDATE_SH_LOGGING=1
  _rotate_log
  if [[ -t 1 ]] && command -v script &>/dev/null; then
    # Interactive: re-run under script(1) so children still see a TTY
    # (progress bars, colours, the `[[ -t 1 ]]` prompt checks below).
    raw_log=$(mktemp)
    rc=0
    script -q -e -c "$(printf '%q ' "$0" "$@")" "$raw_log" || rc=$?
    # script(1) adds its own "Script started/done" header/footer lines.
    _clean_log < "$raw_log" | grep -v '^Script \(started\|done\) on ' >> "$UPDATE_LOG"
    rm -f "$raw_log"
    _log_hint
    exit "$rc"
  else
    # Non-interactive (cron, piped): tee a cleaned copy into the log.
    exec > >(tee >(_clean_log >> "$UPDATE_LOG")) 2>&1
    trap _log_hint EXIT
  fi
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
# Helpers live in update.d/lib.sh; each step is a sourced update.d/NN-*.sh
# (sourced, not executed, so they share RESULTS, flags and set -euo pipefail).
UPDATE_D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/update.d"
# shellcheck source=update.d/lib.sh
source "$UPDATE_D/lib.sh"

# ── Single instance ───────────────────────────────────────────────────────────
# The login tmux pane (0SHORTCUTS/0STARTUP) and the update-all systemd timer
# can both start a run; two at once would fight over flake.lock, apt's lock,
# brew, etc. The lock is held by the process doing the work (the script(1)
# wrapper above has already exec'd/exited by now) and released on exit.
exec {UPDATE_LOCK_FD}>"$(dirname "$UPDATE_LOG")/update.lock"
if ! flock -n "$UPDATE_LOCK_FD"; then
  warn "Another update.sh run is already in progress — exiting."
  exit 0
fi

# ── Setup ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIX_FLAKE_DIR="$SCRIPT_DIR/nix"

START_TIME=$(date +%s)
echo ""
echo -e "${BOLD}System Update — $(date '+%Y-%m-%d %H:%M:%S')${NC}"
$DRY_RUN && echo -e "${YELLOW}[DRY RUN MODE — nothing will be changed]${NC}"

# Source Nix environment so nix/home-manager commands are available
NIX_DAEMON_PROFILE="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
# shellcheck source=/dev/null
[[ -f "$NIX_DAEMON_PROFILE" ]] && . "$NIX_DAEMON_PROFILE"

# Source Homebrew environment if installed
if [[ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# npm global prefix for AI CLIs (mirrors shell.nix sessionVariables)
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$HOME/.nix-profile/bin:$HOME/.cargo/bin:$PATH"

# ── Steps ─────────────────────────────────────────────────────────────────────
# shellcheck source=update.d/10-nix.sh
source "$UPDATE_D/10-nix.sh"
# shellcheck source=update.d/20-apt.sh
source "$UPDATE_D/20-apt.sh"
# shellcheck source=update.d/30-brew.sh
source "$UPDATE_D/30-brew.sh"
# shellcheck source=update.d/40-npm.sh
source "$UPDATE_D/40-npm.sh"
# shellcheck source=update.d/50-flatpak.sh
source "$UPDATE_D/50-flatpak.sh"
# shellcheck source=update.d/60-uv.sh
source "$UPDATE_D/60-uv.sh"
# shellcheck source=update.d/70-appman.sh
source "$UPDATE_D/70-appman.sh"
# shellcheck source=update.d/80-distrobox.sh
source "$UPDATE_D/80-distrobox.sh"

# Nix GC + Docker prune run on their own weekly timer (weekly-cleanup.timer
# in nix/modules/weekly-cleanup.nix).

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
           "age-pin llm-agents" "age-pin sops-nix" "age-pin tuxManager" "age-pin ie-r" \
            "age-pin delta" "age-pin context7" "age-pin rea" "age-pin orca" \
           "Nix flake update" "home-manager switch" "chromium-suid-sandbox restart" \
           "apt" "Homebrew" "brew bundle sync" "npm globals" "Flatpak" "uv install new" "uv tools" "AppMan" "appman install new" "appman update" "Distrobox"; do
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

# Report which top-level (home.packages) packages the Nix step upgraded.
if [[ -n "${HM_PKG_CHANGES:-}" ]]; then
  echo -e "${BOLD}━━━ Nix top-level package changes ━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "$HM_PKG_CHANGES"
  echo ""
elif $UPDATE_NIX && ! $DRY_RUN && command -v nix &>/dev/null; then
  info "No top-level Nix package version changes."
  echo ""
fi

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
if [[ ${#FAILED[@]} -gt 0 ]]; then exit 1; fi

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
