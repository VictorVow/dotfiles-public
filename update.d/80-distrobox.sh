# shellcheck shell=bash disable=SC2034  # vars are read by update.sh / other steps
# Sourced by update.sh — not executable on its own. Shares update.sh's
# variables (RESULTS, flags, colours) and helpers from update.d/lib.sh.

# ── 8. Distrobox containers ───────────────────────────────────────────────────
step "8/8  Distrobox containers"

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
