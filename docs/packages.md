# Package Inventory

Full list of what's managed where and why.

## Nix Home Manager (`nix/modules/packages.nix`)

These replace the old apt, Homebrew, pipx, and npm global package lists.

### System Monitoring
| Package | Replaces | Notes |
|---------|----------|-------|
| `btop` | apt | Rich terminal system monitor |
| `htop` | apt | Interactive process viewer (also configured in `programs.nix`) |
| `nvtop` | — | GPU monitor for NVIDIA/AMD/Intel |
| `cpulimit` | — | Limit CPU usage of a process |
| `vnstat` | apt | Network traffic monitor (CLI; daemon stays in apt) |
| `inxi` | — | Hardware detection and system info |
| `fastfetch` | — | System info on terminal start |

### Containers / Virtualisation
| Package | Replaces | Notes |
|---------|----------|-------|
| `distrobox` | apt | OCI containers integrated with the host |
| `crun` | — | OCI runtime for rootless containers |
| `passt` | — | Networking for user-mode containers |
| `rootlesskit` | — | User namespace helper |
| `virt-manager` | — | GUI for QEMU/KVM VMs (daemon stays in system) |

### File Management
| Package | Replaces | Notes |
|---------|----------|-------|
| `rclone` | — | Cloud storage sync |
| `recoll` | — | Full-text desktop search |
| `gocryptfs` | — | Encrypted overlay filesystem (KDE Plasma Vault) |

### Terminal Tools
| Package | Replaces | Notes |
|---------|----------|-------|
| `screen` | apt | Classic terminal multiplexer |
| `tmux` | apt | Modern terminal multiplexer (also in `programs.nix`) |
| `micro` | — | Terminal editor with sane keybindings |
| `lynx` | — | Text-only web browser |

### Security
| Package | Replaces | Notes |
|---------|----------|-------|
| `gnupg` | apt | GPG encryption and signing |
| `firejail` | — | Application sandboxing |

### Hardware / Peripherals
| Package | Replaces | Notes |
|---------|----------|-------|
| `piper` | — | GUI for configuring gaming mice |
| `solaar` | — | Logitech Unifying receiver manager |
| `libratbag` | — | HID++ device configuration daemon |

### Networking
| Package | Notes |
|---------|-------|
| `sniffnet` | Network traffic monitor (which apps are using the network) |

### Media
| Package | Replaces | Notes |
|---------|----------|-------|
| `haruna` | — | KDE media player (native, lower CPU than Flatpak) |
| `mediainfo` | — | CLI media file analysis |
| `mediainfoGui` | — | GUI for mediainfo |
| `mpv` | — | Lightweight media player |
| `streamlink` | — | Extract streams from websites to a player |
| `pavucontrol` | apt | PulseAudio volume control |
| `speechd` | — | Firefox TTS / SpeechSynthesis API |
| `simplescreenrecorder` | — | Screen recorder with hardware encoding |
| `puddletag` | — | Audio tag editor |
| `yt-dlp` | pipx | Download video/audio from 1000+ sites |

### Torrenting
| Package | Replaces | Notes |
|---------|----------|-------|
| `ktorrent` | — | KDE BitTorrent client |
| `jackett` | brew | Torrent indexer proxy |

### Gaming
| Package | Replaces | Notes |
|---------|----------|-------|
| `lutris` | apt (via PPA) | Open-source gaming platform |
| `steam` | — | Valve game platform (requires `allowUnfree`) |
| `gamemode` | — | Feral's game performance optimiser |
| `gamescope` | — | Valve micro-compositor (FSR, resolution scaling) |
| `wine` | — | Windows compatibility layer |

### Communication
| Package | Notes |
|---------|-------|
| `signal-desktop` | Encrypted messaging (requires `allowUnfree`) |

### Development
| Package | Replaces | Notes |
|---------|----------|-------|
| `git` | apt | Version control |
| `git-lfs` | apt | Large file storage |
| `gh` | brew | GitHub CLI |
| `gitAndTools.gitCredentialLibsecret` | — | KDE Wallet credential storage |
| `rustup` | brew | Rust toolchain manager |
| `jdk17` | — | OpenJDK 17 |
| `mono` | apt | .NET/Mono runtime |
| `dotnet-sdk` | brew | Microsoft .NET SDK |
| `clojure` | brew | Clojure language |
| `ruby` | brew | Ruby runtime |
| `python3` | apt | Python 3 interpreter |
| `poetry` | pipx | Python dependency management |
| `uv` | pipx | Fast Python package manager |
| `virtualenv` | pip | Python virtual environments |
| `nodejs_22` | npm (global) | Node.js LTS + npm |
| `nodePackages.typescript` | npm -g | TypeScript compiler |
| `nodePackages.corepack` | npm -g | Yarn/pnpm version manager |
| `deno` | npm -g | Secure JS/TS runtime |
| `nvm` | manual | Node version manager |
| `neovim` | brew | Text editor (also in `programs.nix`) |
| `vscode` | `3rd-party-packages/vscode.sh` | VS Code (requires `allowUnfree`) |
| `ffmpeg` | apt | Video/audio processing |
| `zrok` | brew | Peer-to-peer tunnel |

### Android / Mobile
| Package | Replaces | Notes |
|---------|----------|-------|
| `android-tools` | — | adb and fastboot |
| `scrcpy` | — | Mirror/control Android devices |
| `androidStudioPackages.stable` | `android-studio.sh` (PPA) | Official Android IDE; uses `buildFHSEnv`; `ANDROID_HOME` from `shell.nix` |

### Utilities
| Package | Replaces | Notes |
|---------|----------|-------|
| `key-mon` | pipx | Display keyboard/mouse on screen for screencasts |
| `gnome-disk-utility` | — | Format USB drives (exFAT) |
| `sqlitebrowser` | — | SQLite GUI |
| `starship` | brew | Shell prompt (also in `programs.nix`) |
| `syncthing` | apt | File sync (also in `services.syncthing`) |
| `sniffnet` | — | Network monitor |

---

## Program Configurations (`nix/modules/programs.nix`)

These use Home Manager's `programs.*` modules to manage config files and integrations, not just install binaries.

| Program | What's configured |
|---------|------------------|
| `git` | userName, email, signing key, credential helpers, push defaults, aliases |
| `git.lfs` | LFS filter hooks |
| `tmux` | Split keybindings (h/v), pane borders, PREFIX indicator, mouse, scrollback |
| `starship` | Shell init injection; theme via `nix/dotfiles/starship.toml` |
| `neovim` | Default editor, vim/vi aliases, basic vimrc (numbers, clipboard, tabs) |
| `htop` | Tree view, CPU display |
| `nix-index` | `nix-locate` + command-not-found integration |
| `syncthing` | User-level systemd service |
| `claude-code` | Settings, hooks, MCP integration, agents, slash commands |
| `codex` | Package pin, MCP integration |
| `gemini-cli` | Package pin (settings omitted — HM#8654 auth bug) |

---

## System Packages (`ansible.yml`)

These require root and stay in Ansible.

| Package | Reason |
|---------|--------|
| `kio-admin` | KDE Dolphin root access — system integration |
| `plasma-gamemode` | KDE Plasma gamemode integration — system integration |
| `plasma-discover-backend-flatpak` | KDE Discover Flatpak backend — system integration |
| `flatpak` | System-wide Flatpak runtime and D-Bus integration |
| `earlyoom` | OOM killer daemon — system service |
| `logiops` | Advanced Logitech customisation — system service + `/etc/logiops.yml` |
| `postfix` | MTA for cron error mail — system service |
| `power-profiles-daemon` | Power management D-Bus service |
| `vnstat` | Network monitor daemon — system service |
| `libva-wayland2` / `libva-drm2` / `libva-glx2` | Shadow PC GPU acceleration — system libraries |
| `libvdpau1` | Shadow PC VDPAU — system library |
| `libcurl4` | Shadow PC client dependency — system library |
| `libayatana-appindicator3-1` | Tray icon support for Lutris — system library |
| `xdg-desktop-portal-gnome` | Flameshot/NormCap Wayland support |
| `gdebi` / `synaptic` | Ubuntu GUI tools for .deb packages |
| `python3-pip` / `pipx` | System Python tooling |
| `apt-transport-https` / `software-properties-common` / `wget` / `gpg` | apt infrastructure |

---

## 3rd-Party Scripts (`3rd-party-packages/`)

These tools ship their own apt repositories or require proprietary installers.

| Script | Installs | Notes |
|--------|----------|-------|
| `docker.sh` | Docker CE | Official Docker apt repo |
| `mullvad-vpn.sh` | Mullvad VPN | Official Mullvad apt repo |
| `android-studio.sh` | Android Studio | PPA (superseded by `androidStudioPackages.stable` in Nix; skips if Nix binary detected) |
| `vscode.sh` | VS Code | Microsoft apt repo (superseded by `vscode` in Nix) |
| `brew.sh` | Homebrew | Linux Homebrew (fills gaps until tools land in Nix) |
| `nix.sh` | Nix | Determinate Systems installer (called by `bootstrap.sh`) |
| `ngrok.sh` | ngrok | Official ngrok apt repo |
| `lutris.sh` | Lutris | Debian repo (superseded by `lutris` in Nix) |
| `dnvm.sh` | dnvm | .NET version manager from GitHub |

---

## Flatpak Apps

Managed via `flatpak.sh` (setup) and `update.sh` (updates). Not tracked individually in this repo — use `flatpak list` to see what's installed.

Notable apps that stay in Flatpak:
- **Discord** — no satisfactory Nix package; Flatpak has better Wayland integration
- **Brave Browser** — Flatpak provides auto-updates
- **Logseq** — no Nix package
- **Heroic Games Launcher** — GOG/Epic games
- **GitKraken** — proprietary git GUI
- **Mullvad VPN** — GUI (daemon is via `mullvad-vpn.sh`)

---

## npm `~/.npm-global` (AI CLI tools)

Managed by the activation script in `nix/modules/shell.nix`. Installed on first `home-manager switch`, not updated automatically.

| Package | Binary | Notes |
|---------|--------|-------|
| `cline` | `cline` | Cline LLM CLI |
| `@continuedev/cli` | `continue` | Continue Dev LLM CLI |
| `opencode-ai` | `opencode` | OpenCode agentic AI |
| `@githubnext/github-copilot-cli` | `github-copilot-cli` | Copilot CLI |

To upgrade: `npm update -g --prefix ~/.npm-global`
