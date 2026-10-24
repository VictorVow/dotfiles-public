# shellcheck shell=bash disable=SC2034  # vars are read by update.sh / other steps
# Sourced by update.sh — not executable on its own. Shares update.sh's
# variables (RESULTS, flags, colours) and helpers from update.d/lib.sh.

# ── 2. apt (system packages) ─────────────────────────────────────────────────
step "2/8  apt (system packages)"

if ! command -v apt-get &>/dev/null; then
  warn "apt-get not found — not an apt-based system?"
  RESULTS["apt"]="skipped (no apt)"
else
  # These exact command lines are NOPASSWD in /etc/sudoers.d/update-all
  # (ansible.yml) — change both together. Noninteractive + keep-old-conffile so
  # an unattended run never stops at a debconf or conffile prompt (new
  # upstream configs land as *.dpkg-dist).
  _apt_upgrade() {
    local noninteractive=(/usr/bin/env DEBIAN_FRONTEND=noninteractive)
    local keep_conf=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
    as_root /usr/bin/apt-get update -qq &&
      as_root "${noninteractive[@]}" /usr/bin/apt-get upgrade -y --with-new-pkgs "${keep_conf[@]}" &&
      as_root "${noninteractive[@]}" /usr/bin/apt-get autoremove -y
  }
  run_step "apt" _apt_upgrade
  success "apt done."
fi
