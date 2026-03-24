{ config, pkgs, lib, ... }:

# Declarative Distrobox container definitions.
#
# Two containers are managed here:
#   1. "dev"   — ubuntu:24.04  — development tools in the Debian/Ubuntu ecosystem
#   2. "media" — fedora:latest — media production tools in the Fedora/RPM ecosystem
#
# Containers are created and initialised via Home Manager activation scripts.
# `distrobox create` is idempotent — it is safe to re-run if the container
# already exists. Package installation uses a sentinel file to avoid
# reinstalling packages on every `home-manager switch`.
#
# To enter a container interactively:
#   distrobox enter dev
#   distrobox enter media
#
# To run a one-off command in a container:
#   distrobox enter dev   -- cmake --version
#   distrobox enter media -- ffmpeg -version
{
  home.activation.distroboxContainers =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Require distrobox and podman to be available before proceeding.
      if ! command -v distrobox &>/dev/null; then
        echo "WARNING: distrobox not found in PATH; skipping container setup."
        echo "         Run 'home-manager switch' again after distrobox is available."
        return 0
      fi

      SENTINEL_DIR="$HOME/.local/share/distrobox-hm-init"
      $DRY_RUN_CMD mkdir -p "$SENTINEL_DIR"

      # ── Container 1: dev (ubuntu:24.04) ──────────────────────────────────────
      # Purpose: Development tools that integrate best with the Debian/Ubuntu
      # ecosystem — build toolchains, debuggers, language runtimes.
      #
      # The --no-entry flag creates the container without launching a shell.
      # --volume is not needed because distrobox auto-mounts $HOME by default.

      $DRY_RUN_CMD distrobox create \
        --name dev \
        --image ubuntu:24.04 \
        --yes \
        --no-entry \
        2>/dev/null || true   # Silently skip if container already exists

      # Install dev packages on first initialisation only.
      # Delete ~/.local/share/distrobox-hm-init/dev-initialized to re-run.
      if [ ! -f "$SENTINEL_DIR/dev-initialized" ]; then
        echo "Initialising 'dev' container packages (this may take a few minutes)..."
        $DRY_RUN_CMD distrobox enter dev -- bash -c "
          sudo apt-get update -qq && \
          sudo apt-get install -y --no-install-recommends \
            build-essential \    # gcc, g++, make, libc-dev — the base build toolchain
            cmake \              # Cross-platform build system generator
            ninja-build \        # Fast build system often used with cmake
            gdb \                # GNU Debugger
            valgrind \           # Memory error detector and profiler
            clang \              # LLVM-based C/C++ compiler
            llvm \               # LLVM compiler infrastructure
            pkg-config \         # Helper tool for compile flags of installed libraries
            libssl-dev \         # OpenSSL development headers
            python3-full \       # Python 3 with all standard library modules
            python3-pip \        # Python package installer
            python3-venv \       # Python virtual environment support
            nodejs \             # Node.js JavaScript runtime
            npm \                # Node Package Manager
            curl \               # HTTP client (useful inside the container)
            wget \               # File downloader
            git                  # Version control (container-local copy)
        " && $DRY_RUN_CMD touch "$SENTINEL_DIR/dev-initialized" \
          || echo "WARNING: 'dev' container package install failed; will retry next switch."
      fi

      # ── Container 2: media (fedora:latest) ───────────────────────────────────
      # Purpose: Media production tools that are better maintained in the
      # Fedora/RPM ecosystem — particularly multimedia codecs, OBS, and video
      # editors which benefit from RPMFusion.

      $DRY_RUN_CMD distrobox create \
        --name media \
        --image fedora:latest \
        --yes \
        --no-entry \
        2>/dev/null || true   # Silently skip if container already exists

      # Install media packages on first initialisation only.
      # Delete ~/.local/share/distrobox-hm-init/media-initialized to re-run.
      if [ ! -f "$SENTINEL_DIR/media-initialized" ]; then
        echo "Initialising 'media' container packages (this may take a few minutes)..."
        $DRY_RUN_CMD distrobox enter media -- bash -c "
          # Enable RPM Fusion for codec support in OBS, ffmpeg, etc.
          sudo dnf install -y --quiet \
            https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-\$(rpm -E %fedora).noarch.rpm \
            https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-\$(rpm -E %fedora).noarch.rpm \
          && sudo dnf install -y --quiet \
            ffmpeg \            # Video/audio processing (RPMFusion build with all codecs)
            obs-studio \        # Open Broadcaster Software — streaming and recording
            kdenlive \          # KDE video editor
            HandBrake-cli \     # Video transcoder CLI
            mpv \               # Lightweight media player
            yt-dlp \            # Download video/audio from 1000+ sites
            mediainfo \         # Media file analysis CLI tool
            mediainfo-gui \     # GUI for mediainfo
            curl \
            wget
        " && $DRY_RUN_CMD touch "$SENTINEL_DIR/media-initialized" \
          || echo "WARNING: 'media' container package install failed; will retry next switch."

        # Export GUI apps from the media container to the host desktop.
        # This creates .desktop entries so OBS and Kdenlive appear in the app launcher.
        if [ -f "$SENTINEL_DIR/media-initialized" ]; then
          $DRY_RUN_CMD distrobox-export --app obs-studio  --container media 2>/dev/null || true
          $DRY_RUN_CMD distrobox-export --app kdenlive    --container media 2>/dev/null || true
        fi
      fi
    '';
}
