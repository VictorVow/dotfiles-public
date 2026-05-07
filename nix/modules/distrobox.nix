{ config, pkgs, lib, ... }:

# Declarative Distrobox container definitions.
#
# Two containers are managed here:
#   1. "fedora" — fedora:latest    — Trivalent browser (hardened Chromium) from secureblue repo
#   2. "arch"   — archlinux:latest — AUR packages (logitune, rsiedit-bin)
#
# Container creation and package installs are each gated by a sentinel file so
# `home-manager switch` is a no-op on normal runs.
#
# Package installs run via `podman exec --user root` to bypass the nosuid
# restriction on container overlay filesystems (which prevents sudo from
# working in non-interactive activation hook contexts).
#
# To enter a container interactively:
#   distrobox enter fedora
#   distrobox enter arch
#
# To run a one-off command in a container:
#   distrobox enter fedora -- ls
#   distrobox enter arch   -- pacman -Q
#
# To force container re-creation (also re-runs package init):
#   rm ~/.local/share/distrobox-hm-init/fedora-created
#   rm ~/.local/share/distrobox-hm-init/arch-created
#
# To re-run package initialisation only (container already exists):
#   rm ~/.local/share/distrobox-hm-init/fedora-initialized
#   rm ~/.local/share/distrobox-hm-init/arch-initialized
#
# To export an app:
#   distrobox enter arch -- distrobox-export --app logitune
#
{
  home.activation.distroboxContainers =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      DISTROBOX="${pkgs.distrobox}/bin/distrobox"
      PODMAN="${pkgs.podman}/bin/podman"

      # Activation runs with a stripped PATH; add required tools.
      export PATH="${pkgs.podman}/bin:${pkgs.crun}/bin:${pkgs.passt}/bin:${pkgs.gawk}/bin:${pkgs.util-linux}/bin:${pkgs.coreutils}/bin:$PATH"

      # Rootless podman needs XDG_RUNTIME_DIR to locate the user's containers.
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"

      SENTINEL_DIR="$HOME/.local/share/distrobox-hm-init"
      $DRY_RUN_CMD mkdir -p "$SENTINEL_DIR"

      # ── Container 1: fedora (fedora:latest) ─────────────────────────────────
      # Purpose: Trivalent browser — a hardened, security-focused Chromium
      # browser from the secureblue project.

      if [ ! -f "$SENTINEL_DIR/fedora-created" ]; then
        echo "Creating 'fedora' container (first run)..."
        $DRY_RUN_CMD timeout 60 "$DISTROBOX" create \
          --name fedora \
          --image fedora:latest \
          --yes \
          --no-entry \
          >/dev/null 2>&1 || true
        $DRY_RUN_CMD timeout 30 "$PODMAN" start fedora 2>/dev/null || true
        $DRY_RUN_CMD touch "$SENTINEL_DIR/fedora-created"
      fi

      # Install Trivalent on first initialisation only.
      # Delete ~/.local/share/distrobox-hm-init/fedora-initialized to re-run.
      if [ ! -f "$SENTINEL_DIR/fedora-initialized" ]; then
        echo "Initialising 'fedora' container packages (this may take a few minutes)..."
        if $DRY_RUN_CMD "$PODMAN" exec --user root fedora bash -c '
          rpm --import https://repo.secureblue.dev/secureblue.gpg && \
          curl -o /etc/yum.repos.d/secureblue.repo \
            https://repo.secureblue.dev/secureblue.repo && \
          dnf install -y --quiet \
            trivalent
        '; then
          $DRY_RUN_CMD touch "$SENTINEL_DIR/fedora-initialized"

          # Export Trivalent to the host desktop.
          DISTROBOX_EXPORT="${pkgs.distrobox}/bin/distrobox-export"
          $DRY_RUN_CMD "$DISTROBOX_EXPORT" --app trivalent --container fedora 2>/dev/null || true
        else
          echo "WARNING: 'fedora' container package install failed; will retry next switch."
        fi
      fi

      # ── Container 2: arch (archlinux:latest) ───────────────────────────────
      # Purpose: AUR access — packages not available on Fedora or Ubuntu.

      if [ ! -f "$SENTINEL_DIR/arch-created" ]; then
        echo "Creating 'arch' container (first run)..."
        $DRY_RUN_CMD timeout 60 "$DISTROBOX" create \
          --name arch \
          --image archlinux:latest \
          --yes \
          --no-entry \
          --pre-init-hooks "cp /etc/pacman.conf /tmp/pacman.conf.bak && sed -i s/^SigLevel.*/SigLevel=Never/ /etc/pacman.conf && pacman -Sy --noconfirm archlinux-keyring && pacman-key --init && pacman-key --populate archlinux && cp /tmp/pacman.conf.bak /etc/pacman.conf" \
          >/dev/null 2>&1 || true
        $DRY_RUN_CMD timeout 30 "$PODMAN" start arch 2>/dev/null || true

        # Wait for distrobox init to complete on first creation. Distrobox runs
        # pacman -Syu during init; distrobox-enter blocks until the container
        # user is available, which signals completion.
        $DRY_RUN_CMD timeout 120 "$DISTROBOX" enter --name arch -- true 2>/dev/null || true

        $DRY_RUN_CMD touch "$SENTINEL_DIR/arch-created"
      fi

      # Per-package sentinels live alongside the container sentinel so new AUR
      # packages can be added without forcing a rebuild of already-installed ones.
      # Delete the relevant arch-<pkg>-initialized sentinel to re-run a single package.

      # Install arch packages on first initialisation only.
      # Delete ~/.local/share/distrobox-hm-init/arch-initialized to re-run.
      if [ ! -f "$SENTINEL_DIR/arch-initialized" ]; then
        echo "Initialising 'arch' container packages (this may take a few minutes)..."
        if $DRY_RUN_CMD "$PODMAN" exec --user root arch bash -c '
          # Distrobox creates /.distroboxrc early in its init, before running
          # setup_pacman (pacman -S -y -y) and pacman -Syu.  Give setup_pacman
          # time to start and acquire the lock before we check for it.
          sleep 15 &&

          # Wait for ALL distrobox pacman operations to finish.
          while [ -f /var/lib/pacman/db.lck ]; do sleep 3; done &&

          pacman -S --noconfirm --needed base-devel git &&

          # Create a dedicated non-root user for makepkg (it refuses to run as root).
          useradd -m aurbuild 2>/dev/null || true &&

          # Build logitune from the AUR.
          # Strategy: install pacman deps as root first, then build with
          # makepkg -d (no dep-sync) as aurbuild, then install as root.
          # This avoids the nosuid overlay limitation that prevents sudo from
          # working inside non-interactive podman exec activation contexts.
          rm -rf /tmp/aur-logitune &&
          git clone https://aur.archlinux.org/logitune.git /tmp/aur-logitune &&
          chown -R aurbuild /tmp/aur-logitune &&

          # Source PKGBUILD and pre-install declared dependencies as root.
          (cd /tmp/aur-logitune &&
            source ./PKGBUILD 2>/dev/null &&
            ALL_DEPS=("''${depends[@]}" "''${makedepends[@]}") &&
            [[ ''${#ALL_DEPS[@]} -gt 0 ]] &&
            pacman -S --noconfirm --needed "''${ALL_DEPS[@]}") || true &&

          # Build without dep-install (already handled above).
          runuser -s /bin/bash -c "cd /tmp/aur-logitune && makepkg -d --noconfirm" aurbuild &&

          # Install the built package as root.
          pacman -U --noconfirm /tmp/aur-logitune/*.pkg.tar.zst
        '; then
          $DRY_RUN_CMD touch "$SENTINEL_DIR/arch-initialized"

          # Export logitune to the host desktop.
          DISTROBOX_EXPORT="${pkgs.distrobox}/bin/distrobox-export"
          $DRY_RUN_CMD "$DISTROBOX_EXPORT" --app logitune --container arch 2>/dev/null || true
        else
          echo "WARNING: 'arch' container package install failed; will retry next switch."
        fi
      fi

      # rsiedit-bin (AUR): C# GUI for editing SS14 RSI sprite files.
      # Delete ~/.local/share/distrobox-hm-init/arch-rsiedit-initialized to re-run.
      if [ ! -f "$SENTINEL_DIR/arch-rsiedit-initialized" ]; then
        echo "Installing rsiedit-bin in 'arch' container (this may take a few minutes)..."
        if $DRY_RUN_CMD "$PODMAN" exec --user root arch bash -c '
          while [ -f /var/lib/pacman/db.lck ]; do sleep 3; done &&

          pacman -S --noconfirm --needed base-devel git &&
          useradd -m aurbuild 2>/dev/null || true &&

          rm -rf /tmp/aur-rsiedit-bin &&
          git clone https://aur.archlinux.org/rsiedit-bin.git /tmp/aur-rsiedit-bin &&
          chown -R aurbuild /tmp/aur-rsiedit-bin &&

          (cd /tmp/aur-rsiedit-bin &&
            source ./PKGBUILD 2>/dev/null &&
            ALL_DEPS=("''${depends[@]}" "''${makedepends[@]}") &&
            [[ ''${#ALL_DEPS[@]} -gt 0 ]] &&
            pacman -S --noconfirm --needed "''${ALL_DEPS[@]}") || true &&

          runuser -s /bin/bash -c "cd /tmp/aur-rsiedit-bin && makepkg -d --noconfirm" aurbuild &&

          pacman -U --noconfirm /tmp/aur-rsiedit-bin/*.pkg.tar.zst
        '; then
          $DRY_RUN_CMD touch "$SENTINEL_DIR/arch-rsiedit-initialized"

          # Export RSIEdit to the host desktop. distrobox-export 1.8.2.2 has no
          # --container flag (it bails with "Invalid flag"), so it must be run
          # *inside* the container via distrobox-enter. The --app match is
          # case-sensitive against the .desktop Name field ("RSIEdit").
          $DRY_RUN_CMD "$DISTROBOX" enter --name arch -- distrobox-export --app RSIEdit 2>/dev/null || true
        else
          echo "WARNING: rsiedit-bin install failed; will retry next switch."
        fi
      fi
    '';
}
