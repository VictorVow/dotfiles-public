# shellcheck shell=bash disable=SC2034  # vars are read by update.sh / other steps
# Sourced by update.sh — not executable on its own. Shares update.sh's
# variables (RESULTS, flags, colours) and helpers from update.d/lib.sh.

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

# sudo for the root steps. Their exact command lines are NOPASSWD in
# /etc/sudoers.d/update-all (ansible.yml), so they never prompt. Without a TTY
# (the systemd timer) use -n so a sudoers mismatch fails the step instead of
# hanging on a password prompt nobody can answer; interactive runs keep the
# prompt as a fallback.
as_root() {
  if [[ -t 0 ]]; then sudo "$@"; else sudo -n "$@"; fi
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
