# shellcheck shell=bash disable=SC2034  # vars are read by update.sh / other steps
# Sourced by update.sh — not executable on its own. Shares update.sh's
# variables (RESULTS, flags, colours) and helpers from update.d/lib.sh.

# ── 3. Homebrew ───────────────────────────────────────────────────────────────
step "3/9  Homebrew"

if ! command -v brew &>/dev/null; then
  skipped "brew not found — skipping."
  RESULTS["Homebrew"]="skipped (not installed)"
else
  # brew update: fetches latest formula definitions
  # brew upgrade: upgrades installed formulae to latest versions
  run_step "Homebrew" bash -c "brew update && brew upgrade"

  # Sync declared state: install new entries, remove unlisted ones.
  # (`install --cleanup` was removed upstream; cleanup is its own subcommand.)
  # Per-host list when there is one (Brewfile.lord on lord-ubuntu).
  BREWFILE="$SCRIPT_DIR/Brewfile"
  [[ -f "$BREWFILE.$HM_CONFIG" ]] && BREWFILE="$BREWFILE.$HM_CONFIG"
  run_step "brew bundle sync" bash -c "
    brew bundle install --file='$BREWFILE' && \
    brew bundle cleanup --force --file='$BREWFILE'
  "

  success "Homebrew done."
fi
