# shellcheck shell=bash disable=SC2034  # vars are read by update.sh / other steps
# Sourced by update.sh — not executable on its own. Shares update.sh's
# variables (RESULTS, flags, colours) and helpers from update.d/lib.sh.

# ── 2. apt (system packages) ─────────────────────────────────────────────────
step "2/8  apt (system packages)"

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
