{ config, pkgs, lib, ... }:

# Declarative Distrobox container definitions.
#
# Three containers are managed here:
#   1. "dev"    — ubuntu:24.04  — development tools in the Debian/Ubuntu ecosystem
#   2. "media"  — fedora:latest — media production tools in the Fedora/RPM ecosystem
#   3. "fedora" — fedora:latest — Trivalent browser (hardened Chromium) from secureblue repo
#
# Containers are created and initialised via Home Manager activation scripts.
# `distrobox create` is idempotent — it is safe to re-run if the container
# already exists. Package installation uses a sentinel file to avoid
# reinstalling packages on every `home-manager switch`.
#
# Package installs run via `podman exec --user root` to bypass the nosuid
# restriction on container overlay filesystems (which prevents sudo from
# working in non-interactive activation hook contexts).
#
# To enter a container interactively:
#   distrobox enter dev
#   distrobox enter media
#
# To run a one-off command in a container:
#   distrobox enter dev   -- cmake --version
#   distrobox enter media -- ffmpeg -version
#
# To re-run package initialisation:
#   rm ~/.local/share/distrobox-hm-init/dev-initialized
#   rm ~/.local/share/distrobox-hm-init/media-initialized
#   rm ~/.local/share/distrobox-hm-init/fedora-initialized
{
  home.activation.distroboxContainers =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      DISTROBOX="${pkgs.distrobox}/bin/distrobox"
      PODMAN="${pkgs.podman}/bin/podman"

      # Activation runs with a stripped PATH; add required tools.
      export PATH="${pkgs.podman}/bin:${pkgs.crun}/bin:${pkgs.passt}/bin:${pkgs.gawk}/bin:${pkgs.util-linux}/bin:$PATH"

      # Rootless podman needs XDG_RUNTIME_DIR to locate the user's containers.
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"

      SENTINEL_DIR="$HOME/.local/share/distrobox-hm-init"
      $DRY_RUN_CMD mkdir -p "$SENTINEL_DIR"

      # ── Container 1: dev (ubuntu:24.04) ────────────────────────────────────
      # Purpose: Development tools that integrate best with the Debian/Ubuntu
      # ecosystem — build toolchains, debuggers, language runtimes.

      $DRY_RUN_CMD "$DISTROBOX" create \
        --name dev \
        --image ubuntu:24.04 \
        --yes \
        --no-entry \
        >/dev/null 2>&1 || true

      # Start the container so podman exec can reach it.
      $DRY_RUN_CMD "$PODMAN" start dev 2>/dev/null || true

      # Install dev packages on first initialisation only.
      # Delete ~/.local/share/distrobox-hm-init/dev-initialized to re-run.
      if [ ! -f "$SENTINEL_DIR/dev-initialized" ]; then
        echo "Initialising 'dev' container packages (this may take a few minutes)..."
        if $DRY_RUN_CMD "$PODMAN" exec --user root dev bash -c '
          apt-get update -qq &&
          apt-get install -y --no-install-recommends \
            build-essential \
            cmake \
            ninja-build \
            gdb \
            valgrind \
            clang \
            llvm \
            pkg-config \
            libssl-dev \
            python3-full \
            python3-pip \
            python3-venv \
            nodejs \
            npm \
            curl \
            wget \
            git
        '; then
          $DRY_RUN_CMD touch "$SENTINEL_DIR/dev-initialized"
        else
          echo "WARNING: 'dev' container package install failed; will retry next switch."
        fi
      fi

      # ── Container 2: media (fedora:latest) ─────────────────────────────────
      # Purpose: Media production tools that are better maintained in the
      # Fedora/RPM ecosystem — particularly multimedia codecs, OBS, and video
      # editors which benefit from RPMFusion.

      $DRY_RUN_CMD "$DISTROBOX" create \
        --name media \
        --image fedora:latest \
        --yes \
        --no-entry \
        >/dev/null 2>&1 || true

      $DRY_RUN_CMD "$PODMAN" start media 2>/dev/null || true

      # Install media packages on first initialisation only.
      # Delete ~/.local/share/distrobox-hm-init/media-initialized to re-run.
      if [ ! -f "$SENTINEL_DIR/media-initialized" ]; then
        echo "Initialising 'media' container packages (this may take a few minutes)..."
        if $DRY_RUN_CMD "$PODMAN" exec --user root media bash -c '
          dnf install -y --quiet \
            https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
            https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
          dnf install -y --quiet \
            ffmpeg \
            obs-studio \
            kdenlive \
            HandBrake-cli \
            mpv \
            yt-dlp \
            mediainfo \
            mediainfo-gui \
            curl \
            wget
        '; then
          $DRY_RUN_CMD touch "$SENTINEL_DIR/media-initialized"

          # Export GUI apps from the media container to the host desktop.
          DISTROBOX_EXPORT="${pkgs.distrobox}/bin/distrobox-export"
          $DRY_RUN_CMD "$DISTROBOX_EXPORT" --app obs-studio --container media 2>/dev/null || true
          $DRY_RUN_CMD "$DISTROBOX_EXPORT" --app kdenlive   --container media 2>/dev/null || true
        else
          echo "WARNING: 'media' container package install failed; will retry next switch."
        fi
      fi

      # ── Container 3: fedora (fedora:latest) ─────────────────────────────────
      # Purpose: Trivalent browser — a hardened, security-focused Chromium
      # browser from the secureblue project.

      $DRY_RUN_CMD "$DISTROBOX" create \
        --name fedora \
        --image fedora:latest \
        --yes \
        --no-entry \
        >/dev/null 2>&1 || true

      $DRY_RUN_CMD "$PODMAN" start fedora 2>/dev/null || true

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
    '';
}
