# shellcheck shell=bash disable=SC2034  # vars are read by update.sh / other steps
# Sourced by update.sh — not executable on its own. Shares update.sh's
# variables (RESULTS, flags, colours) and helpers from update.d/lib.sh.

# ── 5. Flatpak ────────────────────────────────────────────────────────────────
step "5/9  Flatpak"

if ! command -v flatpak &>/dev/null; then
  skipped "flatpak not found — skipping."
  RESULTS["Flatpak"]="skipped (not installed)"
else
  # Update user-installed Flatpak apps. --noninteractive avoids prompts in cron.
  run_step "Flatpak" \
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
