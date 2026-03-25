{ config, pkgs, lib, ... }:

# All user-level packages managed by Home Manager.
# These replace the apt, pipx, npm, and Homebrew package lists in ansible.yml.
#
# Packages that CANNOT be managed here and remain in ansible.yml:
#   - System services: logiops, earlyoom, postfix, power-profiles-daemon, vnstat
#   - KDE/system integration: kio-admin, plasma-gamemode, plasma-discover-backend-flatpak
#   - System libraries (Shadow PC): libva-*, libvdpau1, libcurl4, libayatana-appindicator3-1
#   - System portals: xdg-desktop-portal-gnome
#   - Ubuntu-only GUI tools: gdebi, synaptic
#   - Third-party daemons: mullvad-vpn (via mullvad-vpn.sh), docker (via docker.sh)
#   - Android Studio (via android-studio.sh; also available as androidStudioPackages.stable below)
#   - Flatpak (system-level integration)
{
  home.packages = with pkgs; [

    # ── Android / Mobile ─────────────────────────────────────────────────────
    android-tools  # Provides adb and fastboot
    # Mirror and control Android devices over USB/network.
    # Wrapped to force XWayland (SDL_VIDEODRIVER=x11) because nixpkgs-unstable
    # ships sdl2-compat-2.32.64 (SDL3 compat shim) as pkgs.SDL2. Under Wayland,
    # the SDL2→SDL3 renderer name translation fails:
    #   "Could not create renderer: Parameter 'renderer' is invalid"
    # Forcing x11 uses XWayland where the renderer name mapping works correctly.
    (pkgs.symlinkJoin {
      name = "scrcpy";
      paths = [ scrcpy ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/scrcpy \
          --set SDL_VIDEODRIVER x11
      '';
    })

    # ── System Monitoring ─────────────────────────────────────────────────────
    btop     # Better top - rich terminal system monitor
    htop     # Interactive process viewer
    nvtopPackages.full
             # GPU monitor (like htop for NVIDIA/AMD/Intel GPUs)
    cpulimit # Limit CPU usage of a process; used in Yakuake for etesync-dav
             # Note: cgroups is a better-maintained alternative (different method)
    vnstat   # Network traffic monitor (user CLI; daemon stays in apt)
    inxi     # Hardware detection and system info (e.g. check which GPU is detected)
    fastfetch # Fast system information tool (neofetch alternative)

    # ── Container / Virtualisation ────────────────────────────────────────────
    distrobox    # Create and manage OCI containers integrated with the host
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

    # ── Security / Privacy ────────────────────────────────────────────────────
    gnupg   # GNU Privacy Guard — GPG encryption and signing
    firejail # Sandboxing tool for running applications in restricted environments

    # ── Hardware / Peripherals ────────────────────────────────────────────────
    piper   # GTK application for configuring gaming mice (uses ratbagd)
    solaar  # Logitech Unifying receiver / Bolt manager
            # Note: logiops (for advanced Logitech customisation) stays in apt
            # because it requires a system service and /etc/logiops.yml
    libratbag # (piper dependency) HID++ device configuration daemon

    # ── Networking ────────────────────────────────────────────────────────────
    sniffnet # Network traffic monitor — shows which apps are using the network
             # Similar to GlassWire on Windows
    ngrok    # Secure tunnels to localhost — replaces 3rd-party-packages/ngrok.sh

    # ── Media Playback ────────────────────────────────────────────────────────
    # KDE media player — hardware video decoding works better than Flatpak
    # and CPU usage is lower than the Flatpak version.
    # Wrapped to fix crash on startup:
    #   QT_QPA_PLATFORM=xcb  — force XWayland (Wayland plugin SIGABRTs)
    #   QT_XCB_GL_INTEGRATION=xcb_egl  — use EGL instead of GLX because
    #     XWayland's GLX fails to find a matching FBConfig:
    #     "qglx_findConfig: Failed ... Could not initialize GLX"
    (pkgs.symlinkJoin {
      name = "haruna";
      paths = [ haruna ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/haruna \
          --set QT_QPA_PLATFORM xcb \
          --set QT_XCB_GL_INTEGRATION xcb_egl
      '';
    })
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

    # ── Gaming ────────────────────────────────────────────────────────────────
    lutris    # Open-source gaming platform (Wine/Proton/native games)
    steam     # Valve's game distribution platform (requires allowUnfree = true)
    gamemode  # Feral Interactive's game performance optimiser
    gamescope # Valve's micro-compositor for gaming (FSR, resolution scaling)
              # Note: plasma-gamemode (KDE integration) stays in apt
    wine      # Windows application compatibility layer

    # ── Communication ─────────────────────────────────────────────────────────
    signal-desktop # Encrypted messaging (requires allowUnfree = true)

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
    jdk17        # OpenJDK 17 (JDK + JRE) — needed for Minecraft (Prism Launcher),
                 # Remnants of the Precursors, and other Java apps
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
    nodejs_22    # Node.js LTS runtime (includes npm)
    nodePackages.typescript # TypeScript compiler (replaces npm install -g typescript)
    # nodejs_22 already provides corepack; do not add the standalone package or
    # Home Manager will hit a bin/corepack collision in the profile build.
    deno         # Secure JavaScript/TypeScript runtime (replaces npm install -g deno)

    # ── Development: Tools & Editors ──────────────────────────────────────────
    # neovim — managed by programs.neovim in programs.nix (installs it automatically)
    # vscode — managed by programs.vscode in programs.nix (installs it automatically)

    # Android Studio — uncomment to install via Nix instead of android-studio.sh.
    # Note: ~3 GB download; may require setting STUDIO_JDK on non-NixOS.
    # androidStudioPackages.stable

    # ── Development: Utilities ────────────────────────────────────────────────
    ffmpeg  # Video/audio processing Swiss army knife
    zrok    # Peer-to-peer reverse proxy / tunnel (replaces brew install zrok)

    # ── System Administration ─────────────────────────────────────────────────
    ansible  # IT automation — used to run ansible.yml after bootstrap
             # Provides ansible-playbook, ansible-galaxy, etc.

    # ── System / CLI Utilities ────────────────────────────────────────────────
    screenkey # Display keyboard input on screen — useful for screencasts

    # ── Prompt / Terminal UI ──────────────────────────────────────────────────
    starship # Cross-shell prompt written in Rust (replaces brew install starship)
             # Also configured via programs.starship in programs.nix

    # ── Syncing ───────────────────────────────────────────────────────────────
    syncthing # Continuous file synchronisation (replaces apt install syncthing)
              # Start manually with: syncthing serve

    glow # Markdown viewer
  ];
}
