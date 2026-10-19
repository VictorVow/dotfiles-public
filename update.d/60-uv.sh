# shellcheck shell=bash disable=SC2034  # vars are read by update.sh / other steps
# Sourced by update.sh — not executable on its own. Shares update.sh's
# variables (RESULTS, flags, colours) and helpers from update.d/lib.sh.

# ── 6. uv tools ───────────────────────────────────────────────────────────────
step "6/8  uv tools"

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
