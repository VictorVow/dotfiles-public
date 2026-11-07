# shellcheck shell=bash disable=SC2034  # vars are read by update.sh / other steps
# Sourced by update.sh — not executable on its own. Shares update.sh's
# variables (RESULTS, flags, colours) and helpers from update.d/lib.sh.

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
  # --disable-notifications comments out the notify-send calls in each app's
  # AM-updater so upgrades don't fire a desktop notification per app.
  run_step "appman update" appman -u --disable-notifications
  success "AppMan done."
fi
