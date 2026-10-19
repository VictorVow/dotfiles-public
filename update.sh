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
#   6. uv tools            — Python CLI tools declared in uv-tools.txt
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
#   0 10 * * * /home/boss/Projects/installs/update.sh >/dev/null 2>&1
#
# Every run is logged to ~/.local/state/update-all/update.log (5 MB cap, then
# rotated to update.log.1).

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
GC_NIX=true
DRY_RUN=false

# Minimum age (in days) of the upstream commit each pinned flake input is
# advanced to. For nixpkgs this is the age of the channel *release* (when Hydra
# published it), not the commit date. Older releases are reliably covered by
# Hydra's binary cache, so home-manager switch downloads pre-built artifacts
# rather than compiling.
# Override via env: PIN_AGE_DAYS=21 ./update.sh
PIN_AGE_DAYS="${PIN_AGE_DAYS:-14}"

# Same idea, but for llm-agents.nix (gemini/codex/opencode/... CLIs). numtide
# rebuilds and republishes its binary cache (cache.numtide.com) daily, so a
# 1-day floor is enough to reliably hit the cache without going stale for
# weeks like nixpkgs. Override via env: PIN_AGE_DAYS_LLM_AGENTS=2 ./update.sh
PIN_AGE_DAYS_LLM_AGENTS="${PIN_AGE_DAYS_LLM_AGENTS:-1}"

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
    | tail -1 \
    || true  # empty on failure — callers handle it; don't trip `set -e`
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

# Find the newest NixOS channel release (nixos-unstable, nixos-YY.MM) that was
# *published* at least <days> ago. Echoes the 40-char SHA; empty + non-zero on
# failure or for non-nixos channels.
#
# Why not _latest_commit_at_least_n_days_old for nixpkgs: a commit's committer
# date is when it was made, not when it reached the branch. PRs merged into
# `staging` keep their date, then land on nixos-unstable days or weeks later
# in a staging-next merge — so the commit walk can pick a staging-only tree
# that Hydra never built (e.g. 3475f3c, dated 2026-09-18 but only on the
# branch since 2026-09-28: ~600 local builds incl. perl/gettext/ncurses).
#
# Channel releases are exactly the revisions Hydra fully built before
# advancing the channel. nix-releases' S3 bucket keeps one object per release
# (nixos/<unstable|YY.MM>/nixos-<ver>.<shortrev>) whose LastModified is the
# publish time; its git-revision file holds the full SHA.
_latest_channel_release_at_least_n_days_old() {
  local channel="$1" days="$2"
  local dir
  case "$channel" in
    nixos-unstable)           dir="nixos/unstable" ;;
    nixos-[0-9][0-9].[0-9][0-9]) dir="nixos/${channel#nixos-}" ;;
    *) return 1 ;;
  esac
  local cutoff; cutoff=$(date -u -d "${days} days ago" +%s) || return 1
  # Keys sort lexically by version; starting after last year's releases keeps
  # the listing to the current + previous cycle instead of everything since 2017.
  local start_after="${dir}/nixos-$(( $(date +%y) - 1 ))"
  local token="" page best_key="" best_ts=0 key lm ts
  while :; do
    local args=(-G -s --fail "https://nix-releases.s3.amazonaws.com/"
      --data-urlencode "list-type=2" --data-urlencode "delimiter=/"
      --data-urlencode "prefix=${dir}/nixos-" --data-urlencode "start-after=${start_after}")
    [[ -n "$token" ]] && args+=(--data-urlencode "continuation-token=${token}")
    page=$(curl "${args[@]}") || return 1
    while read -r key lm; do
      ts=$(date -u -d "$lm" +%s 2>/dev/null) || continue
      if (( ts <= cutoff && ts > best_ts )); then best_key="$key"; best_ts=$ts; fi
    done < <(grep -oE '<Key>[^<]+</Key><LastModified>[^<]+' <<<"$page" \
               | sed -E 's|<Key>||; s|</Key><LastModified>| |')
    token=$(grep -oE '<NextContinuationToken>[^<]+' <<<"$page" | sed 's|.*>||') || true
    [[ -z "$token" ]] && break
  done
  [[ -n "$best_key" ]] || return 1
  local sha
  sha=$(curl -sL --fail "https://releases.nixos.org/${best_key}/git-revision") || return 1
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  echo "$sha"
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

# Emit "<name>\t<version>" for each top-level package in a home-manager-path
# store path (the `home-path` of a home-manager generation). Only the direct
# references are listed — that's exactly the `home.packages` set, not the whole
# dependency closure. Multiple outputs of one package (-man/-bin/-dev/…)
# collapse to a single entry.
_hm_toplevel_pkgs() {
  local hmpath="$1"
  [[ -n "$hmpath" && -e "$hmpath" ]] || return 0
  nix-store -q --references "$hmpath" 2>/dev/null \
    | sed 's|^/nix/store/[a-z0-9]\{32\}-||' \
    | awk '
        {
          n = $0
          # Split name vs version at the first "-" that is followed by a digit.
          if (match(n, /-[0-9]/)) { name = substr(n, 1, RSTART-1); ver = substr(n, RSTART+1) }
          else                    { name = n; ver = "" }
          # Drop a trailing Nix output suffix so a pkg and its -man/-bin output
          # collapse to the same (name, version) entry.
          sub(/-(man|bin|dev|devdoc|doc|info|lib|out)$/, "", ver)
          key = name SUBSEP ver
          if (!(key in seen)) { seen[key] = 1; print name "\t" ver }
        }' \
    | sort
}

# Compare the top-level package sets of two home-manager-path store paths and
# echo a formatted list of upgrades / additions / removals (colourised). Echoes
# nothing when the sets are identical. Args: <before-path> <after-path>
_format_hm_pkg_changes() {
  local before="$1" after="$2"
  [[ -n "$before" && -n "$after" && "$before" != "$after" ]] || return 0

  declare -A B=() A=()
  local name ver
  while IFS=$'\t' read -r name ver; do B["$name"]="$ver"; done < <(_hm_toplevel_pkgs "$before")
  while IFS=$'\t' read -r name ver; do A["$name"]="$ver"; done < <(_hm_toplevel_pkgs "$after")

  local -a upgraded=() added=() removed=()
  for name in "${!A[@]}"; do
    if [[ -z "${B[$name]+x}" ]]; then
      added+=("$name|${A[$name]}")
    elif [[ "${B[$name]}" != "${A[$name]}" ]]; then
      upgraded+=("$name|${B[$name]}|${A[$name]}")
    fi
  done
  for name in "${!B[@]}"; do
    [[ -z "${A[$name]+x}" ]] && removed+=("$name|${B[$name]}")
  done

  (( ${#upgraded[@]} + ${#added[@]} + ${#removed[@]} == 0 )) && return 0

  local n o nw v
  if (( ${#upgraded[@]} > 0 )); then
    while IFS='|' read -r n o nw; do
      printf "  ${GREEN}↑${NC} %-30s %s ${DIM}→${NC} %s\n" "$n" "${o:-?}" "${nw:-?}"
    done < <(printf '%s\n' "${upgraded[@]}" | sort)
  fi
  if (( ${#added[@]} > 0 )); then
    while IFS='|' read -r n v; do
      printf "  ${BLUE}+${NC} %-30s %s\n" "$n" "${v:-?}"
    done < <(printf '%s\n' "${added[@]}" | sort)
  fi
  if (( ${#removed[@]} > 0 )); then
    while IFS='|' read -r n v; do
      printf "  ${RED}-${NC} %-30s %s\n" "$n" "${v:-?}"
    done < <(printf '%s\n' "${removed[@]}" | sort)
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
# shellcheck source=/dev/null
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
    # ── gh preflight ──────────────────────────────────────────────────────────
    # The helpers below silence gh's stderr, so a broken auth state (stale
    # keyring token, GITHUB_TOKEN unset by `git su`) or rate limit otherwise
    # shows up only as vague "could not fetch/find" warnings. Surface it once.
    if command -v gh &>/dev/null && ! gh_err=$(gh api rate_limit --jq .resources.core.remaining 2>&1); then
      warn "gh api is failing — GitHub-based checks/pins below will be skipped:"
      echo -e "  ${DIM}${gh_err}${NC}"
      echo -e "  ${DIM}auth: GITHUB_TOKEN $([[ -n "${GITHUB_TOKEN:-}" ]] && echo set || echo unset); see \`gh auth status\`${NC}"
    fi

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

    # ── Age-pin tracked inputs to a ≥<age>-day-old commit ────────────────────
    # Rewrite the SHAs embedded in flake.nix's input URLs to the newest
    # upstream commit on each tracked branch that is at least <age> days old
    # (for nixpkgs: the newest channel release published at least that long
    # ago — see _latest_channel_release_at_least_n_days_old).
    # For nixpkgs/home-manager that age is PIN_AGE_DAYS: by the time a commit
    # is that old, Hydra has fully populated its binary cache for it, so
    # home-manager switch downloads pre-built store paths instead of
    # compiling from source. For llm-agents.nix it's the much shorter
    # PIN_AGE_DAYS_LLM_AGENTS, since numtide republishes cache.numtide.com
    # daily rather than on nixpkgs' slower cadence. Subsequent same-day `hms`
    # runs then reuse those cached paths from flake.lock without further work.
    #
    # The `nix flake update` afterwards reads the new SHAs out of flake.nix
    # and writes them into flake.lock (and refreshes remaining unpinned
    # inputs like tuxManager/ie-r to their HEAD).
    if command -v gh &>/dev/null; then
      info "Age-pinning flake inputs..."
      # Inputs to age-pin: <input-name> <github owner/repo> <min-age-days>
      pin_specs=(
        "nixpkgs NixOS/nixpkgs ${PIN_AGE_DAYS}"
        "nixpkgs-unstable NixOS/nixpkgs ${PIN_AGE_DAYS}"
        "home-manager nix-community/home-manager ${PIN_AGE_DAYS}"
        "llm-agents numtide/llm-agents.nix ${PIN_AGE_DAYS_LLM_AGENTS}"
      )
      for spec in "${pin_specs[@]}"; do
        read -r in_name repo_path age_days <<< "$spec"
        owner="${repo_path%%/*}"
        repo="${repo_path##*/}"
        branch=$(_channel_for_input "$NIX_FLAKE_DIR/flake.nix" "$in_name")
        if [[ -z "$branch" ]]; then
          warn "  ${in_name}: no '# channel:' comment found in flake.nix — skipping age-pin."
          RESULTS["age-pin ${in_name}"]="skipped (no channel comment)"
          continue
        fi
        old_sha=$(_current_input_sha "$NIX_FLAKE_DIR/flake.nix" "$in_name" "$repo_path")
        if [[ "$branch" =~ ^nixos- ]]; then
          # nixpkgs: only ever pin to a Hydra-built channel release (see helper).
          new_sha=$(_latest_channel_release_at_least_n_days_old "$branch" "$age_days") || true
        else
          new_sha=$(_latest_commit_at_least_n_days_old "$owner" "$repo" "$branch" "$age_days") || true
        fi
        if [[ -z "$new_sha" ]]; then
          warn "  ${in_name}: could not find a ≥${age_days}d-old commit on ${branch}."
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
    # refreshes remaining unpinned inputs (tuxManager, ie-r) to their HEAD.
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
  # Snapshot the current top-level package set so we can report which packages
  # the switch upgraded (printed in the summary at the end of the run).
  HM_PROFILE="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager"
  HM_PKGS_BEFORE="$(readlink -f "$HM_PROFILE/home-path" 2>/dev/null || true)"
  # Build logs written after this point are derivations the switch had to
  # compile locally (cache misses) — reported once the switch finishes.
  NIX_BUILD_SINCE="$(date +%s)"
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

  # Diff the top-level package set against the pre-switch snapshot. Stored now
  # (while the profile symlink is fresh) and printed in the summary at the end.
  if ! $DRY_RUN; then
    HM_PKGS_AFTER="$(readlink -f "$HM_PROFILE/home-path" 2>/dev/null || true)"
    HM_PKG_CHANGES="$(_format_hm_pkg_changes "$HM_PKGS_BEFORE" "$HM_PKGS_AFTER")"

    # Which top-level packages needed building rather than substituting, and
    # how long their builds took. Attributes each locally-built derivation to
    # the home.packages entries whose closure contains it. If the switch
    # failed, the profile still points at the old generation, so only the
    # totals line is meaningful.
    HM_PATH_DRV="$(nix-store -q --deriver "$HM_PKGS_AFTER" 2>/dev/null || true)"
    info "Packages built locally during the switch:"
    python3 "$SCRIPT_DIR/scripts/nix-build-report.py" "$NIX_BUILD_SINCE" "$HM_PATH_DRV" \
      || warn "nix-build-report.py failed — build report unavailable."
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
  run_step "brew bundle sync" brew bundle install --cleanup --force-cleanup --file="$SCRIPT_DIR/Brewfile"

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

# ── 6. uv tools ───────────────────────────────────────────────────────────────
step "6/9  uv tools"

if ! command -v uv &>/dev/null; then
  skipped "uv not found — skipping."
  RESULTS["uv tools"]="skipped (not installed)"
else
  # Install anything declared in uv-tools.txt but not yet installed
  # (`uv tool upgrade` only upgrades tools that are already installed).
  # Removal stays manual, as with appman-appimages.txt.
  mapfile -t UV_MISSING < <(
    comm -23 \
      <(sed 's/#.*//' "$SCRIPT_DIR/uv-tools.txt" | tr -d '[:blank:]' | grep -v '^$' | sort -u) \
      <(uv tool list 2>/dev/null | awk '!/^-/ { print $1 }' | sort -u)
  )
  if (( ${#UV_MISSING[@]} )); then
    info "Installing uv tools declared but missing: ${UV_MISSING[*]}"
    run_step "uv install new" bash -c 'for t; do uv tool install "$t" || exit 1; done' _ "${UV_MISSING[@]}"
  else
    RESULTS["uv install new"]="✓ none missing"
  fi

  # Upgrade all uv-managed tools. Tools that live in Nix (yt-dlp, uv, ansible)
  # are not touched here.
  run_step "uv tools" uv tool upgrade --all
  success "uv tools done."
fi

# ── 7. AppMan (AM) — AppImages ────────────────────────────────────────────────
step "7/9  AppMan (AM) — AppImages"

if ! command -v appman &>/dev/null; then
  skipped "appman not found — skipping."
  RESULTS["AppMan"]="skipped (not installed)"
else
  # Install anything declared in appman-appimages.txt but not yet installed
  # (same sync as custom-installers.yml, so new entries don't wait for the next
  # ansible run — `appman -u` only upgrades apps that are already installed).
  # Removal stays manual, as in the playbook.
  mapfile -t APPMAN_MISSING < <(
    comm -23 \
      <(grep -vE '^[[:space:]]*(#|$)' "$SCRIPT_DIR/appman-appimages.txt" | tr -d '[:blank:]' | sort -u) \
      <(NO_COLOR=1 appman -f 2>/dev/null | awk -F'|' '/◆/ { sub(/^[^◆]*◆[[:space:]]*/, "", $1); gsub(/[[:space:]]/, "", $1); print $1 }' | sort -u)
  )
  if (( ${#APPMAN_MISSING[@]} )); then
    info "Installing AppImages declared but missing: ${APPMAN_MISSING[*]}"
    run_step "appman install new" env NO_COLOR=1 appman -i "${APPMAN_MISSING[@]}"
  else
    RESULTS["appman install new"]="✓ none missing"
  fi

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
  #
  # `set -e` is active: a bare `VAR=$(cmd)` assignment aborts the whole script
  # the instant `cmd` exits non-zero — which is exactly what `timeout` does on
  # a wedge (rc 124) or distrobox does on any error. That killed the script
  # here before the rc check below could run. The `|| DBOX_LIST_RC=$?` keeps
  # the assignment in a list context so `set -e` is suppressed and we capture
  # the real exit code instead of crashing.
  DBOX_LIST_RC=0
  DBOX_LIST_OUTPUT=$(timeout 30 distrobox list --no-color 2>/dev/null) || DBOX_LIST_RC=$?
  if [[ $DBOX_LIST_RC -eq 124 ]]; then
    warn "distrobox list timed out — podman may be wedged. Try: pgrep -fa podman ; then kill stuck PIDs and re-run."
    RESULTS["Distrobox"]="✗ list timed out (podman wedged?)"
    DBOX_CONTAINERS=()
  elif [[ $DBOX_LIST_RC -ne 0 ]]; then
    warn "distrobox list failed (rc=$DBOX_LIST_RC) — skipping container upgrades."
    RESULTS["Distrobox"]="✗ list failed (rc=$DBOX_LIST_RC)"
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
           "apt" "Homebrew" "brew install new" "npm globals" "Flatpak" "uv install new" "uv tools" "AppMan" "appman install new" "appman update" "Distrobox" "Nix GC"; do
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
