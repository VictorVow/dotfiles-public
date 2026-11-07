# shellcheck shell=bash disable=SC2034  # vars are read by update.sh / other steps
# Sourced by update.sh — not executable on its own. Shares update.sh's
# variables (RESULTS, flags, colours) and helpers from update.d/lib.sh.

# ── 9. Git commit ─────────────────────────────────────────────────────────────
step "9/9  Git commit"

# Commit the files update.sh itself generated this run (flake pin rewrites,
# flake.lock, flatpak.md, home-manager-news.md) so the tree is clean for the
# next `hms` and lord's `git pull --ff-only` keeps fast-forwarding. Boss only:
# lord never forks the lock (it pulls boss's committed one) and pushing a lord
# commit would break that. Other dirty files are left alone — user work.
if [[ "$HM_CONFIG" != boss ]]; then
  skipped "not boss — this host pulls the committed lock, nothing to commit."
  RESULTS["git commit"]="skipped (not boss)"
elif ! command -v git &>/dev/null; then
  skipped "git not found — skipping."
  RESULTS["git commit"]="skipped (not installed)"
else
  COMMIT_FILES=(nix/flake.nix nix/flake.lock flatpak.md docs/research/home-manager-news.md)
  CHANGED=()
  for f in "${COMMIT_FILES[@]}"; do
    git -C "$SCRIPT_DIR" diff --quiet -- "$f" 2>/dev/null || CHANGED+=("$f")
  done

  if (( ${#CHANGED[@]} == 0 )); then
    info "No update.sh-generated changes to commit."
    RESULTS["git commit"]="✓ clean"
  else
    msg="chore(update-all): update ${CHANGED[*]}"
    run_step "git commit" bash -c '
      set -e
      cd "$1"
      git add -- "${@:3}"
      git commit -qm "$2"
      # Lord pulls --ff-only from origin, so the commit must reach it. If the
      # branch is behind, fast-forward first; if it diverged, rebase this one
      # commit on top. A failed push just warns — next run retries.
      if ! git merge-base --is-ancestor "@{u}" HEAD 2>/dev/null; then
        git pull --ff-only -q 2>/dev/null || git pull --rebase -q
      fi
      git push -q
    ' _ "$SCRIPT_DIR" "$msg" "${CHANGED[@]}"
    info "Committed: ${CHANGED[*]}"
  fi
fi
