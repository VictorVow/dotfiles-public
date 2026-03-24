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
#   - Android Studio (via android-studio.sh)
#   - Flatpak (system-level integration)
{
  home.packages = with pkgs; [

    # ── Android / Mobile ─────────────────────────────────────────────────────
    android-tools  # Provides adb and fastboot
    scrcpy         # Mirror and control Android devices over USB/network

    # ── System Monitoring ─────────────────────────────────────────────────────
    btop     # Better top - rich terminal system monitor
    htop     # Interactive process viewer
    nvtop    # GPU monitor (like htop for NVIDIA/AMD/Intel GPUs)
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
    micro   # Terminal text editor with sane keybindings (nano alternative)
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

    # ── Media Playback ────────────────────────────────────────────────────────
    haruna       # KDE media player — hardware video decoding works better than Flatpak
                 # and CPU usage is lower than the Flatpak version
    mediainfo    # CLI tool for analysing media file properties
    mediainfoGui # GUI for mediainfo
    mpv          # Lightweight and powerful media player
    streamlink   # Extract streams from websites (Twitch, YouTube, etc.) to a player
    pavucontrol  # PulseAudio volume control
                 # Also needed for SongRec (Flatpak, Shazam-based music identification)
    speechd      # Speech Dispatcher — needed for Firefox's SpeechSynthesis API / TTS
                 # in Reader Mode https://support.mozilla.org/en-US/kb/speechd-setup

    # ── Screen Recording / Streaming ─────────────────────────────────────────
    simplescreenrecorder # Screen recorder with hardware encoding support

    # ── Audio / Music ─────────────────────────────────────────────────────────
    puddletag # Audio tag (ID3/etc.) editor

    # ── Video Downloading ─────────────────────────────────────────────────────
    yt-dlp # Download video/audio from YouTube and 1000+ other sites
           # Replaces pipx install of yt-dlp[default]

    # ── Torrenting ────────────────────────────────────────────────────────────
    ktorrent # KDE BitTorrent client
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
    # git-credential-libsecret: stores GitHub credentials in KDE Wallet (libsecret)
    # Package name in nixpkgs may vary; check `nix search nixpkgs git-credential`
    gitAndTools.gitCredentialLibsecret

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
    python3      # Python 3 interpreter
    poetry       # Python dependency management tool (replaces pipx install poetry)
    uv           # Extremely fast Python package/version manager (replaces pipx uv)
    virtualenv   # Python virtual environment creator (python3Packages.virtualenv)

    # ── Development: Node.js ──────────────────────────────────────────────────
    nodejs_22    # Node.js LTS runtime (includes npm)
    nodePackages.typescript # TypeScript compiler (replaces npm install -g typescript)
    nodePackages.corepack   # Manages yarn/pnpm/npm version pinning
                            # (replaces npm install -g corepack)
    deno         # Secure JavaScript/TypeScript runtime (replaces npm install -g deno)
    nvm          # Node Version Manager — manage multiple Node.js versions
                 # Note: `nvm` requires shell integration; see shell.nix

    # ── Development: Tools & Editors ──────────────────────────────────────────
    neovim  # Hyperextensible Vim-based text editor (replaces brew install neovim)
            # Also configured via programs.neovim in programs.nix
    vscode  # Visual Studio Code (replaces 3rd-party-packages/vscode.sh)
            # Requires allowUnfree = true

    # ── Development: Utilities ────────────────────────────────────────────────
    ffmpeg  # Video/audio processing Swiss army knife
    zrok    # Peer-to-peer reverse proxy / tunnel (replaces brew install zrok)

    # ── System / CLI Utilities ────────────────────────────────────────────────
    key-mon  # Display keyboard/mouse input on screen — useful for screencasts
             # Replaces `pipx inject ansible key-mon`
             # Depends on python3Packages.xlib (handled automatically by nixpkgs)

    # ── Monitoring / Indexing ──────────────────────────────────────────────────
    jackett  # (also listed above) Torrent indexer proxy

    # ── Prompt / Terminal UI ──────────────────────────────────────────────────
    starship # Cross-shell prompt written in Rust (replaces brew install starship)
             # Also configured via programs.starship in programs.nix

    # ── Syncing ───────────────────────────────────────────────────────────────
    syncthing # Continuous file synchronisation (replaces apt install syncthing)
              # Also configured as a user service in programs.nix
  ];
}
