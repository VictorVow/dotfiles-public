# shellcheck shell=bash disable=SC2034  # vars are read by update.sh / other steps
# Sourced by update.sh — not executable on its own. Shares update.sh's
# variables (RESULTS, flags, colours) and helpers from update.d/lib.sh.

# ── 1. Nix + Home Manager ────────────────────────────────────────────────────
step "1/8  Nix + Home Manager"

if ! command -v nix &>/dev/null; then
  warn "nix not found — skipping Nix updates. Run ./bootstrap.sh first."
  RESULTS["Nix"]="skipped (not installed)"
else
  if $UPDATE_NIX && [[ "$HM_CONFIG" != boss ]]; then
    # Only boss age-pins and advances flake.lock; other hosts adopt its
    # committed lock so they never fork flake.nix/flake.lock locally.
    info "Pulling the committed flake.lock from boss..."
    run_step "git pull" git -C "$SCRIPT_DIR" pull --ff-only
  elif $UPDATE_NIX; then
    # ── gh preflight ──────────────────────────────────────────────────────────
    # The helpers below silence gh's stderr, so a broken auth state (stale
    # keyring token, GITHUB_TOKEN unset by `git su`) or rate limit otherwise
    # shows up only as vague "could not fetch/find" warnings. Surface it once.
    if command -v gh &>/dev/null && ! gh_err=$(gh api rate_limit --jq .resources.core.remaining 2>&1); then
      warn "gh api is failing — GitHub-based checks/pins below will be skipped:"
      echo -e "  ${DIM}${gh_err}${NC}"
      echo -e "  ${DIM}auth: GITHUB_TOKEN $([[ -n "${GITHUB_TOKEN:-}" ]] && echo set || echo unset); see \`gh auth status\`${NC}"
    fi

    # ── Stable-release upgrade check ──────────────────────────────────────────
    # If the config is pinned to a named stable release (nixos-XX.YY), check
    # whether a newer stable branch has shipped. If so, offer to update both
    # nixpkgs.url and home-manager.url in flake.nix before regenerating the lock.
    # llm-agents.nix is intentionally left untouched (no release versioning).
    if $CHECK_STABLE && command -v gh &>/dev/null; then
      # Read the upstream channel name from the structured `# channel:`
      # comment that precedes the nixpkgs input in flake.nix. The URL itself
      # holds a 40-char SHA (the age-pin), so we can't recover the channel
      # from there.
      current_channel=$(_channel_for_input "$NIX_FLAKE_DIR/flake.nix" nixpkgs)

      if [[ "$current_channel" =~ ^nixos-[0-9]+\.[0-9]+$ ]]; then
        info "Checking for newer nixpkgs stable release (current: $current_channel)..."
        latest_stable=$(_latest_stable_release)

        if [[ -z "$latest_stable" ]]; then
          warn "Could not fetch latest stable release from GitHub — skipping check."
          RESULTS["nixpkgs stable upgrade"]="skipped (fetch failed)"
        elif [[ "$latest_stable" == "$current_channel" ]]; then
          info "nixpkgs is already on the latest stable ($current_channel)."
          RESULTS["nixpkgs stable upgrade"]="✓ up to date"
        else
          echo ""
          warn "New stable release available: ${current_channel} → ${latest_stable}"
          DO_UPGRADE=false
          if $DRY_RUN; then
            echo -e "  ${DIM}[dry-run] Would prompt to upgrade flake.nix to $latest_stable${NC}"
            RESULTS["nixpkgs stable upgrade"]="skipped (dry-run)"
          elif [[ -t 1 ]]; then
            printf "  Upgrade flake.nix to %s? [Y/n] " "$latest_stable"
            read -r STABLE_ANSWER </dev/tty || STABLE_ANSWER="N"
            STABLE_ANSWER="${STABLE_ANSWER:-Y}"
            [[ "$STABLE_ANSWER" =~ ^[Yy]$ ]] && DO_UPGRADE=true
          else
            info "Non-interactive session — skipping stable upgrade."
            info "Run update.sh interactively to upgrade to $latest_stable."
            RESULTS["nixpkgs stable upgrade"]="skipped (non-interactive)"
          fi

          if $DO_UPGRADE; then
            # Rewrite the `# channel:` comments only — the URLs hold SHAs and
            # will be re-pinned to a ≥${PIN_AGE_DAYS}-day-old commit on the
            # NEW channel by the age-pin step below in this same run.
            sed -i \
              -e "s|# channel: ${current_channel}\b|# channel: ${latest_stable}|" \
              "$NIX_FLAKE_DIR/flake.nix"
            # Matching home-manager release branch (nixos-25.11 → release-25.11).
            hm_new="release-${latest_stable#nixos-}"
            hm_old="release-${current_channel#nixos-}"
            sed -i "s|# channel: ${hm_old}\b|# channel: ${hm_new}|" \
              "$NIX_FLAKE_DIR/flake.nix"
            success "flake.nix channel updated: $current_channel → $latest_stable"
            RESULTS["nixpkgs stable upgrade"]="✓ ${current_channel}→${latest_stable}"
          fi
        fi

      elif [[ "$current_channel" =~ ^nixpkgs-unstable$|^nixos-unstable$ ]]; then
        latest_stable=$(_latest_stable_release)
        if [[ -n "$latest_stable" ]]; then
          info "On unstable. Latest stable release is ${latest_stable} (FYI — no action taken)."
        fi
        RESULTS["nixpkgs stable upgrade"]="— (on unstable)"
      fi
    fi

    # ── Age-pin tracked inputs to a ≥<age>-day-old commit ────────────────────
    # Rewrite the SHAs embedded in flake.nix's input URLs to the newest
    # upstream commit on each tracked branch that is at least <age> days old
    # (for nixpkgs: the newest channel release published at least that long
    # ago — see _latest_channel_release_at_least_n_days_old).
    # For nixpkgs/home-manager that age is PIN_AGE_DAYS: by the time a commit
    # is that old, Hydra has fully populated its binary cache for it, so
    # home-manager switch downloads pre-built store paths instead of
    # compiling from source. For llm-agents.nix it's the much shorter
    # PIN_AGE_DAYS_LLM_AGENTS, since numtide republishes cache.numtide.com
    # daily rather than on nixpkgs' slower cadence. Subsequent same-day `hms`
    # runs then reuse those cached paths from flake.lock without further work.
    # Every other input is pinned with PIN_AGE_DAYS_SOURCE / PIN_AGE_DAYS_ORCA
    # as a supply-chain cooldown (see the variables at the top).
    #
    # The `nix flake update` afterwards reads the new SHAs out of flake.nix
    # and writes them into flake.lock. Every direct input is pinned, so it
    # only adds new inputs that aren't in pin_specs yet.
    if command -v gh &>/dev/null; then
      info "Age-pinning flake inputs..."
      # Inputs to age-pin: <input-name> <github owner/repo> <min-age-days>
      pin_specs=(
        "nixpkgs NixOS/nixpkgs ${PIN_AGE_DAYS}"
        "nixpkgs-unstable NixOS/nixpkgs ${PIN_AGE_DAYS}"
        "home-manager nix-community/home-manager ${PIN_AGE_DAYS}"
        "llm-agents numtide/llm-agents.nix ${PIN_AGE_DAYS_LLM_AGENTS}"
        "sops-nix Mic92/sops-nix ${PIN_AGE_DAYS_SOURCE}"
        "tuxManager benapetr/TuxManager ${PIN_AGE_DAYS_SOURCE}"
        "ie-r miaupaw/ie-r ${PIN_AGE_DAYS_SOURCE}"
        "delta zed-industries/delta-nix ${PIN_AGE_DAYS_SOURCE}"
        "context7 upstash/context7 ${PIN_AGE_DAYS_SOURCE}"
        "rea morluto/rea ${PIN_AGE_DAYS_SOURCE}"
        "orca stablyai/orca ${PIN_AGE_DAYS_ORCA}"
        "impeccable pbakaus/impeccable ${PIN_AGE_DAYS_SOURCE}"
        "cli-anything HKUDS/CLI-Anything ${PIN_AGE_DAYS_SOURCE}"
      )
      for spec in "${pin_specs[@]}"; do
        read -r in_name repo_path age_days <<< "$spec"
        owner="${repo_path%%/*}"
        repo="${repo_path##*/}"
        branch=$(_channel_for_input "$NIX_FLAKE_DIR/flake.nix" "$in_name")
        if [[ -z "$branch" ]]; then
          warn "  ${in_name}: no '# channel:' comment found in flake.nix — skipping age-pin."
          RESULTS["age-pin ${in_name}"]="skipped (no channel comment)"
          continue
        fi
        old_sha=$(_current_input_sha "$NIX_FLAKE_DIR/flake.nix" "$in_name" "$repo_path")
        if [[ "$branch" =~ ^nixos- ]]; then
          # nixpkgs: only ever pin to a Hydra-built channel release (see helper).
          new_sha=$(_latest_channel_release_at_least_n_days_old "$branch" "$age_days") || true
        else
          new_sha=$(_latest_commit_at_least_n_days_old "$owner" "$repo" "$branch" "$age_days") || true
        fi
        if [[ -z "$new_sha" ]]; then
          warn "  ${in_name}: could not find a ≥${age_days}d-old commit on ${branch}."
          RESULTS["age-pin ${in_name}"]="✗ fetch failed"
          continue
        fi
        if [[ "$new_sha" == "$old_sha" ]]; then
          info "  ${in_name} (${branch}): up to date (${new_sha:0:7})."
          RESULTS["age-pin ${in_name}"]="✓ up to date"
          continue
        fi
        if $DRY_RUN; then
          echo -e "  ${DIM}[dry-run] would pin ${in_name}: ${old_sha:0:7} → ${new_sha:0:7}${NC}"
          RESULTS["age-pin ${in_name}"]="skipped (dry-run)"
          continue
        fi
        _pin_input_sha "$NIX_FLAKE_DIR/flake.nix" "$in_name" "$repo_path" "$new_sha"
        success "  ${in_name} (${branch}): ${old_sha:0:7} → ${new_sha:0:7}"
        if [[ "$REVIEW_INPUTS" == *" ${in_name} "* ]]; then
          info "    review skill changes: https://github.com/${repo_path}/compare/${old_sha}...${new_sha}"
        fi
        RESULTS["age-pin ${in_name}"]="✓ ${old_sha:0:7}→${new_sha:0:7}"
      done
    else
      warn "gh not available — skipping age-pin step. flake.lock will not advance."
      RESULTS["age-pin nixpkgs"]="skipped (no gh)"
    fi

    # Resolve the (possibly updated) flake.nix URLs into flake.lock. A new
    # input added without a SHA would float to HEAD here — add it to pin_specs.
    info "Updating flake.lock..."
    run_step "Nix flake update" nix flake update --flake "$NIX_FLAKE_DIR"
  else
    info "Skipping flake.lock update (--no-nix). Using locked package versions."
    RESULTS["Nix flake update"]="skipped (--no-nix)"
  fi

  # Apply the (possibly updated) Home Manager configuration.
  # This installs new packages, updates changed ones, and runs activation scripts
  # (including distrobox container creation and npm AI CLI installation).
  # --no-write-lock-file: only update.sh's flake update step is allowed to
  # advance flake.lock; if home-manager switch wanted to write the lock here
  # it would mean an input failed to resolve, which is a real error.
  info "Applying Home Manager configuration..."
  # Snapshot chromium's helper path before switching so we can tell afterwards
  # whether the switch bumped chromium (see the restart block below).
  CHROMIUM_HELPER_BEFORE="$(_chromium_helper_path)"
  # Snapshot the current top-level package set so we can report which packages
  # the switch upgraded (printed in the summary at the end of the run).
  HM_PROFILE="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager"
  HM_PKGS_BEFORE="$(readlink -f "$HM_PROFILE/home-path" 2>/dev/null || true)"
  # Build logs written after this point are derivations the switch had to
  # compile locally (cache misses) — reported once the switch finishes.
  NIX_BUILD_SINCE="$(date +%s)"
  run_step "home-manager switch" \
    home-manager switch --flake "$NIX_FLAKE_DIR#$HM_CONFIG" --no-write-lock-file

  # If the switch bumped Chromium, the version-specific SUID sandbox helper
  # copied to /run/wrappers/bin is now stale and Chromium can refuse to launch
  # until it's refreshed. Restart the installer service to reinstall a matching
  # setuid helper — but only when the helper path actually changed (it encodes
  # the chromium version), so unchanged installs don't touch sudo.
  if [[ -f /etc/systemd/system/chromium-suid-sandbox.service ]]; then
    CHROMIUM_HELPER_AFTER="$(_chromium_helper_path)"
    if [[ -n "$CHROMIUM_HELPER_AFTER" \
          && "$CHROMIUM_HELPER_AFTER" != "$CHROMIUM_HELPER_BEFORE" ]]; then
      info "Chromium changed — refreshing SUID sandbox helper (needs sudo)."
      run_step "chromium-suid-sandbox restart" \
        as_root /usr/bin/systemctl restart chromium-suid-sandbox.service
    else
      skipped "Chromium unchanged — SUID sandbox helper still current."
      RESULTS["chromium-suid-sandbox restart"]="✓ unchanged"
    fi
  fi

  # Diff the top-level package set against the pre-switch snapshot. Stored now
  # (while the profile symlink is fresh) and printed in the summary at the end.
  if ! $DRY_RUN; then
    HM_PKGS_AFTER="$(readlink -f "$HM_PROFILE/home-path" 2>/dev/null || true)"
    HM_PKG_CHANGES="$(_format_hm_pkg_changes "$HM_PKGS_BEFORE" "$HM_PKGS_AFTER")"

    # Which top-level packages needed building rather than substituting, and
    # how long their builds took. Attributes each locally-built derivation to
    # the home.packages entries whose closure contains it. If the switch
    # failed, the profile still points at the old generation, so only the
    # totals line is meaningful.
    HM_PATH_DRV="$(nix-store -q --deriver "$HM_PKGS_AFTER" 2>/dev/null || true)"
    info "Packages built locally during the switch:"
    python3 "$SCRIPT_DIR/scripts/nix-build-report.py" "$NIX_BUILD_SINCE" "$HM_PATH_DRV" \
      || warn "nix-build-report.py failed — build report unavailable."
  fi

  success "Nix / Home Manager done."
fi
