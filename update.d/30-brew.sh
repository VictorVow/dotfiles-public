# shellcheck shell=bash disable=SC2034  # vars are read by update.sh / other steps
# Sourced by update.sh — not executable on its own. Shares update.sh's
# variables (RESULTS, flags, colours) and helpers from update.d/lib.sh.

# ── 3. Homebrew ───────────────────────────────────────────────────────────────
step "3/8  Homebrew"

if ! command -v brew &>/dev/null; then
  skipped "brew not found — skipping."
  RESULTS["Homebrew"]="skipped (not installed)"
else
  # brew update: fetches latest formula definitions
  # brew upgrade: upgrades installed formulae to latest versions
  run_step "Homebrew" bash -c "brew update && brew upgrade"

  # Sync declared state: install new entries, remove unlisted ones.
  # (`install --cleanup` was removed upstream; cleanup is its own subcommand.)
  run_step "brew bundle sync" bash -c "
    brew bundle install --file='$SCRIPT_DIR/Brewfile' && \
    brew bundle cleanup --force --file='$SCRIPT_DIR/Brewfile'
  "

  success "Homebrew done."
fi
