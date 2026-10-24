{ config, pkgs, lib, pkgs-unstable, llm-agents, tuxManager, ie-r, delta, ... }:

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
let
  # llm-agents.nix's own packages output, built against its pinned nixpkgs —
  # matches numtide's binary cache (cache.numtide.com). See home.nix for why
  # this is used instead of the llm-agents overlay.
  llmAgents = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # NeverDecaf's "Chromium Web Store" extension — re-enables installing from
  # the Chrome Web Store on non-Google-branded Chromium builds (ungoogled-chromium
  # doesn't ship Google API keys or the inline-install webstorePrivate API that
  # the store's "Add to Chrome" button relies on). Loaded unpacked via
  # --load-extension since it can't be force-installed from the store itself.
  # Pinned to a specific commit for reproducibility; bump the rev + sha256 to update.
  chromiumWebStoreExt = pkgs.fetchFromGitHub {
    owner = "NeverDecaf";
    repo = "chromium-web-store";
    rev = "8f39cf7477714d8826aadbb12067bd5c0c1af8e3";
    sha256 = "sha256-/pJVNVTjLS3ZaeSkhS9ltCtEH237gVqCnb4S1f/yfD0=";
  };

  # Looking Glass client, bleeding-edge build. nixpkgs only has B7, but the
  # signed Windows IDD is bleeding-only, and the client, IDD and kvmfr kernel
  # module must all come from the SAME upstream commit. To update, bump this
  # rev + hash AND `looking_glass_rev` in custom-installers.yml, then install
  # the matching looking-glass-idd-setup.exe in the guest.
  # See scripts/looking-glass/README.md.
  lookingGlassClient = pkgs.looking-glass-client.overrideAttrs (old: {
    version = "B7-826-236efcb1";
    src = pkgs.fetchFromGitHub {
      owner = "gnif";
      repo = "LookingGlass";
      rev = "236efcb155f952f5d7d9fcd5891a3060ad254e68";
      fetchSubmodules = true;
      hash = "sha256-NAfV4Z0RZp2IGBzVAFysm53aGMEReT03RIN+45TveUU=";
    };
    patches = [ ]; # nixpkgs' nanosvg-unvendor.diff targets B7
    # New since B7: fuse3 (required), libunwind + libdw (crash backtraces),
    # usbredir (emulated USB audio). zstd/libxcb satisfy transitive .pc lookups.
    buildInputs = old.buildInputs ++ (with pkgs; [
      fuse3 libunwind elfutils usbredir libdrm zstd libxcb
    ]);
    postUnpack = ''
      echo B7-826-236efcb1 > source/VERSION
      export sourceRoot="source/client"
    '';
  });
in
{
  home.packages = with pkgs; [
    # How to search for the binary name if which doesn't show it:
    # ls $(nix-store -qR ~/.nix-profile | grep package-name)/bin/

    # ── Android / Mobile ─────────────────────────────────────────────────────
    android-tools  # Provides adb and fastboot
    pkgs-unstable.scrcpy # Mirror and control Android devices over USB/network.
                         # Was briefly on pkgs-latest to get 5.x sooner; nixpkgs-unstable
                         # now ships 5.0.1 (first in channel release 7fd4004d).
    waydroid         # Android container for Linux (binary via Nix; service wired up by ansible.yml)
    waydroid-helper  # Waydroid extension manager: install ARM translation (libhoudini/libndk),
                     # Magisk, GApps helpers. Usage: sudo waydroid-helper (requires root to patch images)

    # ── System Monitoring ─────────────────────────────────────────────────────
    procps   # Provides pgrep, ps, kill, etc.
             # Also included via extraPkgs in the Gaming section for Lutris's
             # internal game bwrap sandbox (both are needed)
    btop     # Better top - rich terminal system monitor
    htop     # Interactive process viewer
    # nvtop — removed from Nix: nvtopPackages.full pulls the entire CUDA 12.8
    # archive (libcublas/cusparse/cusolver/nvjitlink/nvrtc + cuda-merged,
    # ~600 MiB DL / 2.7 GiB unpacked) on every lock bump. Install via apt
    # if needed: `sudo apt install nvtop`.
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
    lookingGlassClient # Looking Glass client: low-latency view of a Windows VM via IVSHMEM/kvmfr
                       # (pinned bleeding build, see let-block; kvmfr module via custom-installers.yml)

    # ── File Management & Backup ──────────────────────────────────────────────
    # rclone — installed by programs.rclone (modules/rclone.nix), which also
    # declaratively manages ~/.config/rclone/rclone.conf and its remotes.
    # recoll — installed by services.recoll (modules/recoll.nix), which also writes
    # recoll.conf and runs the indexer on a timer.
    gocryptfs # Encrypted overlay filesystem; required for KDE Plasma Vault

    # ── Secrets ───────────────────────────────────────────────────────────────
    sops # Edit/rotate age-encrypted secrets (nix/secrets/*.yaml)
    age  # age-keygen + age backend used by sops (identity in Secret Service, sops-age-key.nix)
    gitleaks # Secret scanner — used by scripts/security/ to audit + scrub agent transcripts

    # ── Terminal / Shell Tools ────────────────────────────────────────────────
    tmux    # Terminal multiplexer (modern) — also configured in programs.nix
    # micro — managed by programs.micro in programs.nix (installs it automatically)
    lynx    # Text-only web browser
    ripgrep  # Fast text search
    shellcheck # Static analysis tool for shell scripts

    # ── Security / Privacy ────────────────────────────────────────────────────
    gnupg   # GNU Privacy Guard — GPG encryption and signing
    libsecret # Secret Service client library — needed for logseq-cli
    firejail # Sandboxing tool for running applications in restricted environments

    # ── Hardware / Peripherals ────────────────────────────────────────────────
    ie-r.packages.${pkgs.stdenv.hostPlatform.system}.default
             # System-wide color picker (Wayland + X11) — press hotkey, copies colour to clipboard

    piper   # GTK application for configuring gaming mice (uses ratbagd)
    solaar  # Logitech Unifying receiver / Bolt manager
            # Note: logiops (for advanced Logitech customisation) stays in apt
            # because it requires a system service and /etc/logiops.yml
    libratbag   # (piper dependency) HID++ device configuration daemon
    noisetorch  # Microphone noise suppression via PulseAudio virtual device
                # Replaces manually-installed ~/.local/bin/noisetorch
    # fw-fanctrl — installed via custom-installers.yml (upstream install.sh)
    # because the nixpkgs package only ships the Python CLI; the systemd
    # service, ectool, and system-sleep hooks need root and bundling.

    # ── Networking ────────────────────────────────────────────────────────────
    mosh     # Mobile shell — SSH alternative with roaming and intermittent connectivity support
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
    gpu-screen-recorder     # GPU-accelerated screen recorder (replaces flathub-gpu-screen-recorder.sh)
    gpu-screen-recorder-gtk # GUI frontend for gpu-screen-recorder (replaces Flatpak com.dec05eba.gpu_screen_recorder)

    # ── Audio / Music ─────────────────────────────────────────────────────────
    puddletag # Audio tag (ID3/etc.) editor

    # ── Video Downloading ─────────────────────────────────────────────────────
    yt-dlp # Download video/audio from YouTube and 1000+ other sites
           # Replaces pipx install of yt-dlp[default]

    # ── Torrenting ────────────────────────────────────────────────────────────
    kdePackages.ktorrent # KDE BitTorrent client
    qbittorrent # BitTorrent client; consumes Jackett below as a Torznab search plugin
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
    wineWow64Packages.stable # Windows application compatibility layer
              # Pure 64-bit build using WoW64 mode, still runs 32-bit apps. Plain
              # `wine` is 32-bit-only and drags in a pkgsi686Linux dep chain
              # (mbedtls → ffmpeg → gtk4 → pipewire) that Hydra often fails to
              # cache, forcing multi-hour local builds (or build failures).
    pkgs-unstable.wl-freeze # https://github.com/Zerodya/wl-freeze Suspend/resume the focused game (or any app) on Wayland — bind to a hotkey.
              # Pinned to unstable: KDE Plasma (KWin) support landed in 2.1.0;
              # stable has 2.0.2 (Hyprland/Niri/Sway only).

    # ── Database ──────────────────────────────────────────────────────────────
    sqlitebrowser # GUI browser and editor for SQLite databases

    # ── Development: Version Control ──────────────────────────────────────────
    git      # Distributed version control
    git-lfs  # Git extension for large file storage (binary assets, models, etc.)
    git-filter-repo # Rewrite git history (successor to git filter-branch / BFG)
    gh       # Official GitHub CLI
    glab     # Official GitLab CLI
    forgejo-cli # `fj` — Forgejo client CLI (repos, issues, PRs) via the API
                # Logged in to git.device.example.com (token in ~/.local/share/forgejo-cli/keys.json)
    # `forgejo` — the Forgejo admin CLI can't talk to a remote instance (it reads
    # app.ini + the DB directly), so run it inside the self-hosted container over
    # SSH. Uses the server's own binary, so it always matches the server version.
    (pkgs.writeShellApplication {
      name = "forgejo";
      text = ''
        tty=()
        [[ -t 0 && -t 1 ]] && tty=(-t)
        exec ssh "''${tty[@]}" -i ~/.ssh/boss-XPS-9380 lord@lord-ubuntu \
          docker exec -i "''${tty[@]}" -u git forgejo forgejo "''${@@Q}"
      '';
    })
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
    uv           # Extremely fast Python package/version manager (replaces pipx uv)
    jupyter      # Jupyter Notebook + JupyterLab + ipython REPL + ipykernel
                 # (replaces pipx ipykernel; also provides the python3 interpreter)

    # ── Development: Node.js ──────────────────────────────────────────────────
    # Pinned to Node 24: ships npm >= 11.10, required for the `min-release-age`
    # supply-chain cooldown set in the global ~/.npmrc (see programs.nix). Plain
    # `nodejs` (Node 22) only has npm 10.x, where that key is silently ignored.
    nodejs_24    # Node.js 24 runtime — provides npm >= 11.10 for global installs
                 # and the home-manager activation script; fnm overrides per project
    fnm          # Fast Node Manager — install/switch Node versions per project
                 # Shell integration (auto-switch on cd) is set up in shell.nix
    typescript # TypeScript compiler
    deno         # Secure JavaScript/TypeScript runtime (replaces npm install -g deno)
    # pnpm / yarn for the global supply-chain hardening rc files written in
    # programs.nix (~/.config/pnpm/rc, ~/.yarnrc.yml).
    pnpm         # Tracks newest packaged pnpm. The age-pinned flake.lock is
                 # currently pre-pnpm-11 (≈10.28): `minimum-release-age` (added
                 # in 10.16) is active now; `block-exotic-subdeps` /
                 # `strict-dep-builds` are pnpm-11 keys, ignored by 10.x and
                 # auto-activating once update-all advances the pin to a
                 # nixpkgs with pnpm 11 (where all three are also defaults).
    # yarn via corepack (bundled with nodejs_24): dispatches to each project's
    # packageManager-pinned version instead of one global yarn that shadows —
    # and, for Berry, silently migrates — project lockfiles. A plain
    # `yarn-berry_4` here broke any repo pinned to classic 1.x. The global
    # ~/.yarnrc.yml hardening (shell-apps.nix) still applies to Berry projects
    # corepack runs; classic 1.x ignores it (an accepted gap, as npm does too).
    (writeShellScriptBin "yarn"    ''exec ${nodejs_24}/bin/corepack yarn "$@"'')
    (writeShellScriptBin "yarnpkg" ''exec ${nodejs_24}/bin/corepack yarnpkg "$@"'')

    # ── Development: Tools & Editors ──────────────────────────────────────────
    # neovim   — managed by programs.neovim in programs.nix (installs it automatically)
    # vscode   — installed via custom-installers.yml from packages.microsoft.com;
    #            settings + keybindings are still managed declaratively via
    #            xdg.configFile in programs.nix (see Code/User/{settings,keybindings}.json)
    # vscodium — managed by vscodiumPkg + home.packages in programs.nix
    kdePackages.kate          # KDE text editor with syntax highlighting and plugins
    kdePackages.markdownpart  # KPart for rendering Markdown — enables live preview in Kate
    delta.packages.${pkgs.stdenv.hostPlatform.system}.delta
                              # Zed's Delta (delta.dev) — proprietary prebuilt binary via
                              # the official zed-industries/delta-nix flake
    nixd      # Nix language server — used by Zed's Nix extension (and any LSP client)
    # code-cursor — removed from Nix; nixpkgs repackages each release as a
    # heavy Electron build. Installed via custom-installers.yml from upstream
    # AppImage / .deb instead.

    # androidStudioPackages.stable — removed from Nix; the buildFHSEnv wrapper
    # rebuilds a multi-GB FHS rootfs every time the lock bumps. Reverted to
    # the PPA fallback in custom-installers.yml (ppa:maarten-fonville/android-studio).
    # ANDROID_HOME (set in shell.nix) still applies; existing SDK in
    # ~/Projects/Dev/Android/Sdk continues to work unchanged.

    # ── Development: Utilities ────────────────────────────────────────────────
    ffmpeg  # Video/audio processing Swiss army knife
    just    # Command runner for project-specific tasks (justfile)
    pkgs-unstable.zrok  # Peer-to-peer reverse proxy / tunnel (replaces brew install zrok).
                        # Pinned to unstable: stable nixpkgs lags on zrok 1.x;
                        # unstable has 2.x (1.x dropped the --name-selection flag).

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
    doctl    # Official DigitalOcean CLI — manage droplets, k8s, domains, etc.
             # Authenticate with: doctl auth init
    google-cloud-sdk # `gcloud` — Google Cloud CLI (ts-exit VM in project stremio-selfhosted)
                     # Authenticate with: gcloud auth login
    opentofu # `tofu` — Terraform-compatible IaC; drives Self-Hosted/Terraform/*

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
        VAULT="$HOME/Projects/installs/0SHORTCUTS"

        if [[ ! -d "$VAULT/0STARTUP" ]]; then
          notify-send -u critical "vault-launch" "0SHORTCUTS not found at $VAULT"
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
    # megasync — removed from Nix; nixpkgs builds it from source. Installed via
    # custom-installers.yml using mega.nz/linux/repo (official Debian repo).
    syncthing # Continuous file synchronisation (replaces apt install syncthing)
              # Start manually with: syncthing serve
    syncthingtray # Tray app for Syncthing (replaces pre-built binary)

    # ── Cryptocurrency ───────────────────────────────────────────────────────────────
    ledger-live-desktop # Ledger Live desktop client

    # ── AI / LLM CLIs ─────────────────────────────────────────────────────────
    # Codex is wired up via programs.codex in programs.nix (HM module exists and
    # can merge MCP/settings). Antigravity has no equivalent HM module for the
    # CLI — Home Manager's programs.antigravity wraps the IDE build via
    # mkVscodeModule, which manages ~/.antigravity IDE settings and doesn't
    # apply to the CLI binary. So this entry installs just the CLI as a plain
    # package. Same flake source as codex: llm-agents.packages.${system}
    # (cache.numtide.com) — see the `llmAgents` binding above.
    llmAgents.antigravity-cli  # Google Antigravity CLI (binary: `agy`)
    # OpenCode 2 (binary: `opencode2`; `opencode` is v1, below). Orca detects
    # `opencode2` as its "OpenCode 2" agent. A wrapper that reads FREELLMAPI_API_KEY
    # from its sops file at launch, so only OpenCode (and its children) get the key —
    # it's not exported to shells (see "API tokens: whitelist only" in shell.nix).
    (pkgs.symlinkJoin {
      name = "opencode2-wrapped";
      paths = [ llmAgents.opencode2 ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        rm $out/bin/opencode2
        makeWrapper ${llmAgents.opencode2}/bin/opencode2 $out/bin/opencode2 \
          --run 'export FREELLMAPI_API_KEY="$(cat ${config.sops.secrets.freellmapi_api_key.path} 2>/dev/null)"'
      '';
    })
    # OpenCode 1 (binaries: `opencode` and `opencode1`), for the magpie-community Devin/Cursor
    # provider plugins (config in ai-agents.nix), which are v1-style and don't load
    # in v2. Fully isolated under ~/.opencode1/{config,data,state,cache}: v2 migrated
    # the shared opencode.db and its config uses v2-only keys, so v1 must touch neither.
    (pkgs.symlinkJoin {
      name = "opencode1-wrapped";
      paths = [ (pkgs.writeShellScriptBin "opencode1" ''
        root="$HOME/.opencode1"
        FREELLMAPI_API_KEY="$(cat ${config.sops.secrets.freellmapi_api_key.path} 2>/dev/null)"
        export FREELLMAPI_API_KEY
        export XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data" \
               XDG_STATE_HOME="$root/state" XDG_CACHE_HOME="$root/cache"
        # Mirror ~/.config into the isolated config root so tools launched from
        # sessions (gh, marktext, …) see the user's real config — except
        # `opencode`, whose v1 config must stay separate from v2's.
        for d in "$HOME"/.config/* "$HOME"/.config/.[!.]*; do
          [ -e "$d" ] || continue
          base=''${d##*/}
          [ "$base" = opencode ] && continue
          [ -e "$root/config/$base" ] || ln -s "$d" "$root/config/$base"
        done
        # Drop v2's `--standalone` (e.g. from v2-style resume commands): v1 doesn't
        # know it and prints its help instead of starting.
        args=()
        for a in "$@"; do [ "$a" = --standalone ] || args+=("$a"); done
        exec ${llmAgents.opencode}/bin/opencode "''${args[@]}"
      '') ];
      postBuild = "ln -s opencode1 $out/bin/opencode";
    })
    llmAgents.copilot-cli      # GitHub Copilot CLI — was npm @githubnext/github-copilot-cli
    llmAgents.cursor-agent     # Cursor Agent CLI (binary: `cursor-agent`) — binary fetch, cached by numtide
    pkgs-unstable.devin-cli    # Cognition Devin CLI (binary: `devin`) — not in llm-agents.nix; stable's
                               # build lags far behind. Upstream alternative is `npm i -g devin`.

    # ── Assorted ───────────────────────────────────────────────────────────────
    glow # Markdown viewer
    # rustdesk — removed from Nix; the build pulls libsciter (Rust crate +
    # vendored .so) and rebuilds whenever the rustdesk crate version moves.
    # Installed via custom-installers.yml from official GitHub .deb release.
    # claude-desktop — removed from Nix; the aaddrick flake input rebuilt the
    # .deb on every lock bump. Installed via custom-installers.yml from
    # Anthropic's official apt repository (code.claude.com/docs/en/desktop-linux).
    streamlink-twitch-gui-bin
    suwayomi-server # which tachidesk-server
    amdgpu_top # Tool to display AMDGPU usage

    # ── Chromium-based - needs to be non-Flatpak to retain it's stronger sandboxing ──────────────────────────
    # commandLineArgs bakes in --load-extension so the Chrome Web Store enabler
    # (chromiumWebStoreExt, defined above) is always loaded without manual setup.
    (ungoogled-chromium.override {
      commandLineArgs = "--load-extension=${chromiumWebStoreExt}/src";
    })
    pkgs-unstable.brave-origin  # De-Braved fork of Brave (no crypto/rewards/telemetry cruft).
                                 # Pinned to unstable: too new for the current stable channel.
    # Google-branded Chrome. Needed alongside ungoogled-chromium because the Chrome Web
    # Store's own client-side browser check blocks non-Chrome-branded browsers from
    # installing extensions — no local policy/extension can work around a check that
    # runs on Google's page before install is attempted.
    #
    # Same setuid-sandbox problem as ungoogled-chromium (the Nix store can't hold a
    # setuid-root file), but Google Chrome ignores CHROME_DEVEL_SANDBOX in release
    # builds (verified — it's a locked-down dev-only escape hatch, for obvious
    # privilege-escalation reasons), so unlike ungoogled-chromium this can't be fixed
    # by pointing it at a fixed path via env var. Instead scripts/chromium-suid-sandbox.sh
    # bind-mounts a setuid-root helper directly over this exact store path's
    # share/google/chrome/chrome-sandbox at boot (the chromium_sandbox tag in
    # custom-installers.yml) — re-run it after every google-chrome update since the
    # store path (and thus the bind-mount target) changes.
    google-chrome
  ];

  # Looking Glass client config. lgmp:shmDevice points at the kvmfr char device created
  # by the kernel module (custom-installers.yml) rather than /dev/shm, enabling
  # the DMA-BUF import path recommended for iGPUs.
  xdg.configFile."looking-glass/client.ini".text = ''
    [lgmp]
    shmDevice=/dev/kvmfr0

    [win]
    title=Looking Glass (win11)
    fullScreen=no

    [spice]
    enable=yes
  '';
}
