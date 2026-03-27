# Declarative vs. Imperative State

A map of what system state is managed declaratively (reproducible, version-controlled, can be rebuilt from this repo) versus imperatively (run-once scripts, GUI settings, runtime state).

---

## Declarative — Nix Home Manager (`nix/`)

The primary declarative layer. Running `home-manager switch` atomically applies all of the below. Previous states are retained as generations and can be rolled back.

### User packages

~170 packages declared in `nix/modules/packages.nix`. Covers: system monitoring, containers, development toolchains, media tools, file management, terminal tools, security, hardware (including noisetorch, mouseless), networking, gaming, communication, and Android tooling.

### Program configurations

Declared via `programs.*` in `nix/modules/programs.nix` and `nix/modules/shell.nix`:

| Program | What's declared |
|---------|-----------------|
| git | user identity, GPG signing, credential helper (libsecret) |
| tmux | mouse, scrollback, keybindings, pane management |
| starship | prompt theme (Gruvbox dark powerline) via `dotfiles/starship.toml` |
| neovim | managed as package |
| vscode | managed as package |
| htop | managed as package |
| btop | managed as package |
| micro | managed as package |
| gh | managed as package |
| bash | aliases, PATH, session variables |

### Shell environment

Declared in `nix/modules/shell.nix`:
- PATH additions (Homebrew, Rust/Cargo, npm global, Android SDK, Flatpak, Firefox, fnm, dnvm)
- Session variables: `EDITOR`, `VISUAL`, `GOPATH`, `PODMAN_USERNS`, `GDK_DEBUG`, `MOZ_ENABLE_WAYLAND`, `ANDROID_HOME`, `NPM_CONFIG_PREFIX`
- Aliases: `hms`, `nsp`, `nsh`, `dbe`, `dbl`, `update-all`

### Activation scripts (semi-declarative)

Run on every `home-manager switch`. The declarations are in version control, but the resulting state is not fully reproducible:

| Activation | What it does | Caveat |
|------------|-------------|--------|
| Distrobox containers (`nix/modules/distrobox.nix`) | Creates `dev` (ubuntu:24.04) and `media` (fedora:latest) containers; installs packages on first init | Container-internal package state drifts after initial setup |
| npm AI CLI tools (`nix/modules/shell.nix`) | Installs cline, @continuedev/cli, opencode-ai, codex, copilot-cli, gemini-cli via npm | Install-if-missing only; versions not pinned; not rollback-able |
| Flatpak remote (`nix/modules/shell.nix`) | Adds Flathub as a user remote | Idempotent; does not install apps |

---

## Declarative — Ansible (`ansible.yml`)

Manages state that requires root. Declarative in intent (defines desired state, idempotent), but lacks generation tracking and rollback.

### System packages (apt)

| Category | Packages |
|----------|---------|
| **Encryption** | cryptsetup, cryptsetup-initramfs, gocryptfs |
| **KDE essentials** | sddm, sddm-theme-breeze, dolphin, ark, plasma-runners-addons, kde-spectacle, plasma-widgets-addons, plasma-dataengines-addons, plasma-wallpapers-addons, plasma-calendar-addons, grub-theme-breeze, plymouth-theme-breeze, usb-creator-kde, alsa-base |
| **KDE integration** | kio-admin, plasma-gamemode, plasma-discover-backend-flatpak |
| **Flatpak daemon** | flatpak |
| **System services** | earlyoom, logiops, postfix, power-profiles-daemon, vnstat |
| **System libraries** (Shadow PC GPU) | libva-wayland2, libva-drm2, libva-glx2, libvdpau1, libcurl4 |
| **System tray** | libayatana-appindicator3-1 |
| **XDG portals** | xdg-desktop-portal-gnome |
| **Ubuntu GUI tools** | gdebi, synaptic |
| **System Python** | python3-pip, pipx |
| **apt infrastructure** | apt-transport-https, software-properties-common, wget, gpg |

### 3rd-party install scripts

Ansible discovers and runs all scripts in `3rd-party-packages/`. Each script is idempotent (checks before acting):

| Script | What it installs | Why separate from Ansible |
|--------|-----------------|--------------------------|
| `docker.sh` | Docker CE + Compose from docker.com apt repo | Ships its own apt repo + GPG key |
| `mullvad-vpn.sh` | Mullvad VPN daemon from mullvad.net apt repo | Ships its own apt repo + GPG key |
| `android-studio.sh` | Android Studio via JetBrains PPA | nixpkgs version unreliable on non-NixOS |
| `brew.sh` | Homebrew (Linux) | Fills nixpkgs gaps; some tools only on Homebrew |
| `dnvm.sh` | .NET version manager | Not in nixpkgs; manages multiple SDK versions |

---

## Imperative — Top-level scripts

Run manually as needed. Scripts are in version control but the state they produce is not.

| Script | Role | Idempotent? |
|--------|------|-------------|
| `bootstrap.sh` | One-shot Nix + Home Manager install | Yes |
| `migrate.sh` | Safe one-way migration from apt/brew/pipx/npm to Nix; verifies Nix packages before removing duplicates | Yes |
| `update.sh` | Orchestrates updates across Nix, apt, Homebrew, npm, Flatpak, Distrobox | Yes |
| `flatpak.sh` | Adds Flathub remote; reinstalls apps from `~/.var/app` leftovers on migration | Partial |
| `arkenfox.sh` | Applies Arkenfox Firefox privacy hardening (user.js injection) | Partial |

---

## Not managed / manual state

State that exists on the system but is not tracked in this repo.

| State | Location | Why not managed | Potential path |
|-------|----------|-----------------|----------------|
| **KDE Plasma settings** | `~/.config/kde*`, `~/.config/plasma-*` | GUI-generated, hundreds of INI files, changes constantly | [`plasma-manager`](https://github.com/nix-community/plasma-manager) Home Manager module |
| **Flatpak apps** (~160+) | Flatpak user install | Most lack Nix packages; Flatpak has better Wayland/sandbox support for desktop apps | Keep Flatpak; track app IDs in a text file |
| **Application data/caches** | `~/.config/discord/`, `~/.config/Code/`, `~/.local/share/Steam/`, etc. | Runtime state, changes constantly, not meaningful to version-control | Back up with Vorta/Borg |
| **Distrobox container internals** | Container filesystems | Apt packages inside containers drift after first init | Re-running init or rebuilding containers |
| **logiops config** | `/etc/logiops.yml` | Not yet committed anywhere; created manually or by logiops default | `system-manager` `environment.etc` or commit to repo |
| **Docker daemon config** | `/etc/docker/daemon.json` | Any customisation not tracked | `system-manager` `environment.etc` |
| **Android SDK** | `~/Android/Sdk/` | Managed by Android Studio internally | — |
| **dnvm .NET versions** | `~/.local/share/dnvm/` | Managed by dnvm after initial install | — |
| **npm AI CLI versions** | `~/.npm-global/` | Installed by activation script but not version-pinned | Move to `packages.nix` once upstreamed to nixpkgs |
| **Firefox profile data** | `~/.mozilla/firefox/` | Application state, not config | Arkenfox `user.js` is re-applied by `arkenfox.sh` |
| **ollama** | `/usr/local/bin/ollama` | Local LLM runner; installed from ollama.com installer; being migrated to Nix | `pkgs.ollama` in `packages.nix` |
| **calibre** | `/opt/calibre/` | E-book library manager; installed via official calibre installer script | `pkgs.calibre` in `packages.nix` |
| **Z-Library** | `/opt/Z-Library/` | E-library desktop app; manual download | — |
| **Claude Code CLI** | `~/.local/share/claude/` | AI coding assistant CLI; self-updating binary managed by `claude update` | Keep self-managed; not in nixpkgs |
| **Zed editor** | `~/.local/zed.app/` | Modern code editor; installed via zed.dev install script | `pkgs.zed-editor` in `packages.nix` |
| **JetBrains Rider** | `~/.local/bin/rider` | C# IDE; managed by JetBrains Toolbox or manual archive extract | JetBrains Toolbox manages updates |
| **AppImages (~44)** | `~/AppImages/` | Standalone portable executables (Heynote, Logseq, Cursor, FreeTube, Chiaki, Hydra, Redact, TagSpaces, ledger-live, amdgpu_top, etc.); manual downloads | Keep as-is; maintain a list in `~/AppImages/` |
