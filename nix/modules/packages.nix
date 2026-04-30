{ config, pkgs, lib, tuxManager, ... }:

# All user-level packages managed by Home Manager.
# These replace the apt, pipx, npm, and Homebrew package lists in ansible.yml.
#
# Packages that CANNOT be managed here and remain in ansible.yml:
#   - System services: logiops, earlyoom, postfix, power-profiles-daemon, vnstat
#   - KDE/system integration: kio-admin, plasma-gamemode, plasma-discover-backend-flatpak
#   - System libraries (Shadow PC): libva-*, libvdpau1, libcurl4, libayatana-appindicator3-1
#   - System portals: xdg-desktop-portal-gnome
#   - Ubuntu-only GUI tools: gdebi, synaptic
#   - Third-party daemons: mullvad-vpn (via mullvad-vpn.sh), docker (via docker.sh), tailscale (via tailscale.sh)
#   - Android Studio — now Nix-managed via androidStudioPackages.stable (android-studio.sh retained as fallback)
#   - Flatpak (system-level integration)
{
  home.packages = with pkgs; [
    # How to search for the binary name if which doesn't show it:
    # ls $(nix-store -qR ~/.nix-profile | grep package-name)/bin/

    # ── Android / Mobile ─────────────────────────────────────────────────────
    android-tools  # Provides adb and fastboot
    scrcpy         # Mirror and control Android devices over USB/network
    waydroid         # Android container for Linux (binary via Nix; service wired up by ansible.yml)
    waydroid-helper  # Waydroid extension manager: install ARM translation (libhoudini/libndk),
                     # Magisk, GApps helpers. Usage: sudo waydroid-helper (requires root to patch images)

    # ── System Monitoring ─────────────────────────────────────────────────────
    procps   # Provides pgrep, ps, kill, etc.
             # Also included via extraPkgs in the Gaming section for Lutris's
             # internal game bwrap sandbox (both are needed)
    btop     # Better top - rich terminal system monitor
    htop     # Interactive process viewer
    nvtopPackages.full
             # GPU monitor (like htop for NVIDIA/AMD/Intel GPUs)
    cpulimit # Limit CPU usage of a process; used in Yakuake for etesync-dav
             # Note: cgroups is a better-maintained alternative (different method)
    vnstat   # Network traffic monitor (user CLI; daemon stays in apt)
    inxi     # Hardware detection and system info (e.g. check which GPU is detected)
    fastfetch # Fast system information tool (neofetch alternative)
    tuxManager.packages.${pkgs.stdenv.hostPlatform.system}.default
             # Qt6 GUI system/process manager (TuxManager)

    # ── Container / Virtualisation ────────────────────────────────────────────
    distrobox    # Create and manage OCI containers integrated with the host
    podman       # OCI container backend required by distrobox
    crun         # OCI container runtime; alternative to runc, needed for rootless containers
    passt        # Networking for user-mode containers (distrobox/podman dependency)
    rootlesskit  # User namespace helper for rootless containers
    virt-manager # GUI for managing QEMU/KVM virtual machines
                 # Note: libvirtd daemon is managed by the system (stays in apt/systemd)

    # ── File Management & Backup ──────────────────────────────────────────────
    rclone   # Cloud storage sync (S3, Google Drive, etc.)
    recoll   # Full-text desktop search tool
    gocryptfs # Encrypted overlay filesystem; required for KDE Plasma Vault

    # ── Terminal / Shell Tools ────────────────────────────────────────────────
    screen  # Terminal multiplexer (classic)
    tmux    # Terminal multiplexer (modern) — also configured in programs.nix
    # micro — managed by programs.micro in programs.nix (installs it automatically)
    lynx    # Text-only web browser
    ripgrep  # Fast text search

    # ── Security / Privacy ────────────────────────────────────────────────────
    gnupg   # GNU Privacy Guard — GPG encryption and signing
    firejail # Sandboxing tool for running applications in restricted environments
    veracrypt # On-the-fly disk/file-container encryption (VeraCrypt GUI + CLI)

    # ── Hardware / Peripherals ────────────────────────────────────────────────
    piper   # GTK application for configuring gaming mice (uses ratbagd)
    solaar  # Logitech Unifying receiver / Bolt manager
            # Note: logiops (for advanced Logitech customisation) stays in apt
            # because it requires a system service and /etc/logiops.yml
    libratbag   # (piper dependency) HID++ device configuration daemon
    noisetorch  # Microphone noise suppression via PulseAudio virtual device
                # Replaces manually-installed ~/.local/bin/noisetorch

    # ── Networking ────────────────────────────────────────────────────────────
    sniffnet # Network traffic monitor — shows which apps are using the network
             # Similar to GlassWire on Windows
    ngrok    # Secure tunnels to localhost

    # ── Media Playback ────────────────────────────────────────────────────────
    haruna       # KDE media player — hardware video decoding works better than Flatpak
                 # and CPU usage is lower than the Flatpak version
    mediainfo    # CLI tool for analysing media file properties
    mediainfo-gui # GUI for mediainfo
    mpv          # Lightweight and powerful media player
    streamlink   # Extract streams from websites (Twitch, YouTube, etc.) to a player
    pavucontrol  # PulseAudio volume control
                 # Also needed for SongRec (Flatpak, Shazam-based music identification)
    speechd      # Speech Dispatcher — needed for Firefox's SpeechSynthesis API / TTS
                 # in Reader Mode https://support.mozilla.org/en-US/kb/speechd-setup

    # ── Screen Recording / Streaming ─────────────────────────────────────────
    simplescreenrecorder  # Screen recorder with hardware encoding support
    gpu-screen-recorder   # GPU-accelerated screen recorder (replaces flathub-gpu-screen-recorder.sh)

    # ── Audio / Music ─────────────────────────────────────────────────────────
    puddletag # Audio tag (ID3/etc.) editor

    # ── Video Downloading ─────────────────────────────────────────────────────
    yt-dlp # Download video/audio from YouTube and 1000+ other sites
           # Replaces pipx install of yt-dlp[default]

    # ── Torrenting ────────────────────────────────────────────────────────────
    kdePackages.ktorrent # KDE BitTorrent client
    jackett  # Torrent indexer proxy; used as a qBittorrent search plugin

    # ── Disk / Storage ────────────────────────────────────────────────────────
    gnome-disk-utility # GUI for formatting USBs to exFAT (compatible with all OSes)

    # ── Fonts ─────────────────────────────────────────────────────────────────
    noto-fonts         # Google Noto — broad Unicode coverage, fixes missing-glyph boxes
    noto-fonts-cjk-sans # Noto CJK (Chinese/Japanese/Korean)
    noto-fonts-color-emoji # Noto emoji
    liberation_ttf     # Metrically compatible with Arial/Times New Roman/Courier New
                       # Important for Wine/Lutris — many Windows apps expect these metrics

    # ── Gaming ────────────────────────────────────────────────────────────────
    # gamemode — stays in apt; gamemode-daemon is a system service and the apt
    #            gamemoderun binary avoids the nix bash-wrapper/libc conflict
    gamescope # Valve's micro-compositor for gaming (FSR, resolution scaling)
              # Note: plasma-gamemode (KDE integration) stays in apt
    wine      # Windows application compatibility layer

    # ── Database ──────────────────────────────────────────────────────────────
    sqlitebrowser # GUI browser and editor for SQLite databases

    # ── Development: Version Control ──────────────────────────────────────────
    git      # Distributed version control
    git-lfs  # Git extension for large file storage (binary assets, models, etc.)
    gh       # Official GitHub CLI
    # The legacy gitAndTools wrapper was removed from nixpkgs. Keep using the
    # libsecret credential helper via the Git config in programs.nix.

    # ── Development: Languages & Runtimes ─────────────────────────────────────
    rustup       # Rust toolchain installer (includes cargo and rustc)
                 # Manages stable/beta/nightly toolchains via `rustup toolchain`
    (lib.lowPrio pkgs.jdk17) # OpenJDK 17 — needed for Minecraft (Prism Launcher),
                              # Remnants of the Precursors, and other Java apps;
                              # lowPrio so jdk21 wins file conflicts in buildEnv
    jdk21        # OpenJDK 21 LTS — default Java; required by Suwayomi-Server JAR
    mono         # .NET/Mono runtime — replaces mono-complete apt package
    dotnet-sdk   # Microsoft .NET SDK — for C# development, Grayjay, etc.
    clojure      # Clojure language + deps CLI (was: clojure/tools/clojure in Homebrew)
                 # Useful for Logseq development
    ruby         # Ruby language runtime
    # python3 — provided transitively by pkgs.jupyter below; do not add standalone
    #            or Home Manager's buildEnv will hit a python3 binary conflict
    poetry       # Python dependency management tool (replaces pipx install poetry)
    uv           # Extremely fast Python package/version manager (replaces pipx uv)
    virtualenv   # Python virtual environment creator (python3Packages.virtualenv)
    jupyter      # Jupyter Notebook + JupyterLab + ipython REPL + ipykernel
                 # (replaces pipx ipykernel; also provides the python3 interpreter)

    # ── Development: Node.js ──────────────────────────────────────────────────
    nodejs       # Node.js LTS runtime — provides npm for global installs and
                 # the home-manager activation script; fnm overrides per project
    fnm          # Fast Node Manager — install/switch Node versions per project
                 # Shell integration (auto-switch on cd) is set up in shell.nix
    typescript # TypeScript compiler
    deno         # Secure JavaScript/TypeScript runtime (replaces npm install -g deno)

    # ── Development: Tools & Editors ──────────────────────────────────────────
    # neovim — managed by programs.neovim in programs.nix (installs it automatically)
    # vscode — managed by programs.vscode in programs.nix (installs it automatically)
    kdePackages.kate          # KDE text editor with syntax highlighting and plugins
    kdePackages.markdownpart  # KPart for rendering Markdown — enables live preview in Kate
    code-cursor # AI-powered code editor built on vscode

    androidStudioPackages.stable
    # Official Android IDE (~3 GB on first build). Uses buildFHSEnv internally
    # to handle prebuilt SDK binaries with hardcoded interpreter paths.
    # Replaces the android-studio task in custom-installers.yml (PPA).
    # ANDROID_HOME is set in shell.nix; no additional config needed.
    # See docs/buildFHSEnv.md for details.

    # ── Development: Utilities ────────────────────────────────────────────────
    ffmpeg  # Video/audio processing Swiss army knife
    zrok    # Peer-to-peer reverse proxy / tunnel (replaces brew install zrok)

    (let
      appimagetool-bin = pkgs.runCommand "appimagetool-bin" {
        src = pkgs.fetchurl {
          url = "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage";
          sha256 = "1lmdwwmqyfb5ig9cx24lxzql45had0kmni4alzylaxcn325ll3xr";
        };
      } "install -m755 $src $out";
    in pkgs.writeShellApplication {
      name = "appimagetool";
      text = ''
        exec "${appimagetool-bin}" --appimage-extract-and-run "$@"
      '';
    })
    # appimagetool — not in nixpkgs; fetched as a fixed-output derivation and
    # wrapped to pass --appimage-extract-and-run (required on NixOS without FUSE)

    # ── System Administration ─────────────────────────────────────────────────
    ansible  # IT automation — used to run ansible.yml after bootstrap
             # Provides ansible-playbook, ansible-galaxy, etc.

    # ── System / CLI Utilities ────────────────────────────────────────────────
    screenkey  # Display keyboard input on screen — useful for screencasts
    mouseless  # Keyboard-driven app-switcher overlay
               # Replaces manually-installed ~/.local/bin/mouseless

    # ── App Launcher ─────────────────────────────────────────────────────────
    rofi  # dmenu/launcher with Wayland support (rofi-wayland merged into rofi); invoked by vault-launch
    dex           # .desktop executor — handles Exec= field codes, Flatpak, Terminal=true

    (pkgs.writeShellApplication {
      name = "vault-launch";
      runtimeInputs = [ pkgs.rofi pkgs.dex pkgs.libnotify ];
      text = ''
        VAULT="$HOME/Vaults/gocryptfs1/0SHORTCUTS"

        if [[ ! -d "$VAULT/0STARTUP" ]]; then
          notify-send -u critical "vault-launch" "Vault is not mounted"
          exit 1
        fi

        TMPDIR_LOCAL=$(mktemp -d)
        trap 'rm -rf "$TMPDIR_LOCAL"' EXIT
        INDEX="$TMPDIR_LOCAL/index"   # PATH<TAB>TYPE  (one line per item, tab-separated)
        INPUT="$TMPDIR_LOCAL/input"   # rofi dmenu input (null-byte icon annotations)

        add_item() {
          local path="$1" type="$2" display="$3" icon="$4"
          printf '%s\t%s\n' "$path" "$type" >> "$INDEX"
          if [[ -n "$icon" ]]; then
            printf '%s\x00icon\x1f%s\n' "$display" "$icon" >> "$INPUT"
          else
            printf '%s\n' "$display" >> "$INPUT"
          fi
        }

        process_file() {
          local file="$1"
          local category="" name="" icon="" display=""

          # Category prefix for items inside 1COMMON subdirectories
          if [[ "$file" == "$VAULT/1COMMON/"*"/"* ]]; then
            local rel
            rel="''${file#"$VAULT/1COMMON/"}"
            category="''${rel%%/*}"
          fi

          if [[ "$file" == *.desktop ]]; then
            name=$(grep -m1 "^Name=" "$file" 2>/dev/null | cut -d= -f2-) || true
            [[ -z "$name" ]] && return 0
            icon=$(grep -m1 "^Icon=" "$file" 2>/dev/null | cut -d= -f2-) || true
            display="''${category:+[$category] }$name"
            add_item "$file" "desktop" "$display" "$icon"
          elif [[ -x "$file" ]]; then
            name=$(basename "$file")
            display="''${category:+[$category] }$name"
            add_item "$file" "exec" "$display" ""
          fi
        }

        while IFS= read -r -d "" f; do
          process_file "$f"
        done < <(
          {
            # All of 0SHORTCUTS except .git and 2OTHER (recurse into 1COMMON subdirs)
            find "$VAULT" \
              \( -path "$VAULT/.git" -o -path "$VAULT/2OTHER" \) -prune \
              -o \( -type f -o \( -type l -xtype f \) \) -print0

            # 2OTHER top-level only; -xtype f excludes symlinks pointing to directories
            find "$VAULT/2OTHER" -maxdepth 1 \
              \( -type f -o \( -type l -xtype f \) \) -print0
          } | sort -z
        )

        [[ ! -s "$INPUT" ]] && { notify-send "vault-launch" "No launchable items found"; exit 0; }

        selected_idx=$(rofi -dmenu -show-icons -p " Launch" -i -format "i" -no-custom \
          < "$INPUT" 2>/dev/null) || exit 0
        [[ -z "$selected_idx" ]] && exit 0

        item_path=$(awk -F'\t' -v n="$((selected_idx + 1))" 'NR == n { print $1 }' "$INDEX")
        item_type=$(awk -F'\t' -v n="$((selected_idx + 1))" 'NR == n { print $2 }' "$INDEX")

        case "$item_type" in
          desktop) dex "$item_path" ;;
          exec)    nohup "$item_path" > /dev/null 2>&1 & ;;
        esac
      '';
    })

    # ── Git Utilities ────────────────────────────────────────────────────────
    (pkgs.writeShellApplication {
      name = "git-checkout-fb";
      runtimeInputs = [ pkgs.git ];
      text = ''
        usage() {
          echo "Usage: git checkout-fb <github-url>"
          echo "Example: git checkout-fb https://github.com/owner/repo/tree/branch-name"
          exit 1
        }

        [[ $# -eq 1 ]] || usage

        url="$1"

        if [[ ! "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/tree/(.+)$ ]]; then
          echo "Error: URL must be in format: https://github.com/owner/repo/tree/branch"
          exit 1
        fi

        owner="''${BASH_REMATCH[1]}"
        repo="''${BASH_REMATCH[2]}"
        branch="''${BASH_REMATCH[3]}"
        remote_url="https://github.com/$owner/$repo"

        echo "Fetching $owner/$repo @ $branch"

        # Reuse an existing remote if it already points to the same repo
        added_remote=false
        remote_name=$(git remote -v | awk -v url="$remote_url" '$2 == url && $3 == "(fetch)" {print $1; exit}')

        if [[ -z "$remote_name" ]]; then
          if git remote | grep -q '^fork$'; then
            existing_fork_url=$(git remote get-url fork)
            echo "Error: 'fork' remote already exists pointing to $existing_fork_url"
            echo "Remove it first: git remote remove fork"
            exit 1
          fi
          git remote add fork "$remote_url"
          remote_name="fork"
          added_remote=true
        else
          echo "Using existing remote '$remote_name'"
        fi

        git fetch "$remote_name" "$branch"

        if git show-ref --verify --quiet "refs/heads/$branch"; then
          echo "Note: local branch '$branch' already exists — checking it out (not updated)"
          git checkout "$branch"
        else
          git checkout -b "$branch" FETCH_HEAD
        fi

        if $added_remote; then
          git remote remove fork
        fi

        echo "Done. On branch '$branch' (from $remote_url)"
      '';
    })

    # ── Prompt / Terminal UI ──────────────────────────────────────────────────
    starship # Cross-shell prompt written in Rust (replaces brew install starship)
             # Also configured via programs.starship in programs.nix

    # ── Syncing ───────────────────────────────────────────────────────────────
    megasync  # MEGA Cloud Drive sync client
    syncthing # Continuous file synchronisation (replaces apt install syncthing)
              # Start manually with: syncthing serve
    syncthingtray # Tray app for Syncthing (replaces pre-built binary)

    # ── Cryptocurrency ───────────────────────────────────────────────────────────────
    ledger-live-desktop # Ledger Live desktop client

    # ── Assorted ───────────────────────────────────────────────────────────────
    glow # Markdown viewer
    rustdesk 
    claude-desktop # Official Claude AI desktop app (via aaddrick/claude-desktop-debian)
    jan # ChatBox-like desktop LLM chat app
    streamlink-twitch-gui-bin
    suwayomi-server
    amdgpu_top # Tool to display AMDGPU usage

    # ── Chromium-based - needs to be non-Flatpak to retain it's stronger sandboxing ──────────────────────────
    ungoogled-chromium
  ];
}
