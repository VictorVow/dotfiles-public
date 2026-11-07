# shellcheck shell=bash disable=SC2034  # vars are read by update.sh / other steps
# Sourced by update.sh — not executable on its own. Shares update.sh's
# variables (RESULTS, flags, colours) and helpers from update.d/lib.sh.

# ── 4. npm global AI CLIs ─────────────────────────────────────────────────────
step "4/9  npm global packages (AI CLIs)"

if ! command -v npm &>/dev/null; then
  skipped "npm not found — skipping."
  RESULTS["npm globals"]="skipped (no npm)"
else
  # Declared in npm-globals.txt; installed to ~/.npm-global by shell.nix's activation.
  # npm update -g upgrades ALL packages in the prefix to their latest versions.
  # This is the equivalent of the old ansible `npm install -g <pkg>@latest` loop.
  #
  # Note: yt-dlp was previously updated to a nightly build via pipx.
  # It is now installed via Nix (pkgs.yt-dlp) and updated with the flake above.
  # If you specifically need the nightly build, uncomment the yt-dlp block at
  # the bottom of this file.
  info "Updating AI CLI tools in $NPM_CONFIG_PREFIX ..."
  run_step "npm globals" \
    npm update --global --prefix "$NPM_CONFIG_PREFIX"
  success "npm global packages done."
fi
