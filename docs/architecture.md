# Architecture

This repo manages system configuration through four distinct layers. Each layer has a specific scope — this separation keeps the Nix config portable while still supporting system-level features.

## Layer Diagram

```
┌─────────────────────────────────────────────────────────┐
│  User Space (no root)                                    │
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Nix + Home Manager  (nix/)                     │    │
│  │  • User packages (~/.nix-profile)               │    │
│  │  • Dotfiles (git, tmux, starship, neovim, htop) │    │
│  │  • Shell env (PATH, aliases, session variables) │    │
│  │  • Distrobox containers (dev, media)            │    │
│  │  • Systemd user services (syncthing)            │    │
│  └─────────────────────────────────────────────────┘    │
│                                                          │
│  ┌──────────────────┐  ┌──────────────────────────┐     │
│  │  Flatpak         │  │  npm ~/.npm-global        │     │
│  │  GUI apps (40+)  │  │  AI CLI tools not in Nix  │     │
│  │  (flatpak.sh)    │  │  (shell.nix activation)   │     │
│  └──────────────────┘  └──────────────────────────┘     │
│                                                          │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│  System (root required)                                  │
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Ansible  (ansible.yml)                         │    │
│  │  • KDE Plasma integration packages              │    │
│  │  • System services (earlyoom, logiops, postfix) │    │
│  │  • System libraries (Shadow PC, VA-API)         │    │
│  │  • apt infrastructure (wget, gpg, https)        │    │
│  │  • Runs 3rd-party-packages/ scripts             │    │
│  └─────────────────────────────────────────────────┘    │
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │  3rd-party scripts  (3rd-party-packages/)       │    │
│  │  • Docker (official upstream repo)              │    │
│  │  • Mullvad VPN (official upstream repo)         │    │
│  │  • Android Studio (PPA)                         │    │
│  │  • ngrok, VS Code, Homebrew, etc.               │    │
│  └─────────────────────────────────────────────────┘    │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Why Multiple Layers?

### Nix + Home Manager — user packages and dotfiles

Nix provides reproducible, atomic, rollback-able package management without root. Home Manager extends this to dotfiles and program configuration. Together they replace apt, Homebrew, pipx, and npm globals for user-space tools.

**Why not NixOS?** The system runs Kubuntu, which provides better hardware support, KDE integration, and Ubuntu-specific tooling. Nix runs on top of Ubuntu without replacing it.

### Ansible — system packages

Some things genuinely need root:
- **System services** (earlyoom, logiops, power-profiles-daemon) — managed by systemd at the system level
- **KDE integration packages** (kio-admin, plasma-gamemode) — integrate with KDE at the system level
- **System libraries** (libva-*, libvdpau1) — installed to system paths for GPU/hardware support
- **Flatpak** — requires system-level daemons and D-Bus integration

Ansible handles exactly these and nothing more. Everything that *can* go in Nix *has* gone in Nix.

### 3rd-party scripts — upstream repos

Some tools ship their own apt repositories (Docker, Mullvad VPN) or require proprietary installers (Android Studio). These can't go in nixpkgs and require root for repo setup. The scripts are idempotent (check if installed before acting).

### Flatpak — GUI apps with sandboxing

Many GUI applications (Discord, Brave, Logseq, Heroic Games Launcher, etc.) are distributed as Flatpaks with proper Wayland/portal support and sandboxing. Flatpak is the right tool for these — switching them to Nix packages would often lose the sandboxing and can introduce Wayland compatibility issues. These are managed via `flatpak.sh` and updated via `update.sh`.

### npm `~/.npm-global` — AI CLI tools

Several AI/LLM CLI tools (Cline, OpenCode, Gemini CLI, etc.) are not yet in nixpkgs. They're installed into a user-local npm prefix (no sudo), managed by a Home Manager activation script in `shell.nix`. This is a transitional layer — as these tools land in nixpkgs, they'll move to `packages.nix`.

### JavaScript / Node.js package management

The setup has several layers for JS tooling:

**Base runtime — `nodejs` (Nix, LTS)**
A Nix-managed Node.js LTS provides the `node` and `npm` binaries at `~/.nix-profile/bin/`. This is the default node used for global tooling and by the Home Manager activation script that installs AI CLI tools into `~/.npm-global`. It has no involvement in per-project development — that's fnm's job.

**Per-project versioning — `fnm` (Nix)**
`fnm` (Fast Node Manager) is installed via Nix and configured in `shell.nix` with `eval "$(fnm env --use-on-cd --shell bash)"`. When you `cd` into a project directory containing a `.node-version` or `.nvmrc` file, fnm automatically activates the correct Node.js version. Use `fnm install <version>` and `fnm default <version>` to manage versions. fnm-managed node overrides the Nix base node in that shell.

**Runtimes supported:**
| Runtime | Supported | How |
|---------|-----------|-----|
| Node.js | Yes | Nix `nodejs` (base LTS) + `fnm` (per-project) |
| Deno | Yes | Nix `deno` package — TypeScript-native, no npm required |
| Bun | No | Not in this setup |

**Package managers supported:**
| Tool | Supported | How |
|------|-----------|-----|
| npm | Yes | Comes with `nodejs`; globals go to `~/.npm-global` |
| yarn | Per-project only | `npx yarn` or as a devDependency; not installed globally |
| pnpm | Per-project only | `npx pnpm` or as a devDependency; not installed globally |
| bun | No | Not installed |

## Configuration Flow

```
Edit nix/modules/*.nix
        ↓
hms  (home-manager switch --flake ./nix#boss)
        ↓
Home Manager reads flake.nix → home.nix → modules/
        ↓
Writes files to ~/.nix-profile/, ~/.config/, ~/.local/share/
Activates user services (syncthing)
Runs activation scripts (distrobox containers, npm installs)
```

## Key Files

| File | Purpose |
|------|---------|
| `nix/flake.nix` | Pins nixpkgs-unstable + home-manager versions |
| `nix/home.nix` | User identity, state version, imports all modules |
| `nix/modules/packages.nix` | All `home.packages` — replaces apt/brew/pipx/npm lists |
| `nix/modules/programs.nix` | `programs.*` configs — git, tmux, starship, neovim, htop |
| `nix/modules/shell.nix` | Bash, PATH, session variables, aliases, npm AI CLI activation |
| `nix/modules/distrobox.nix` | Declarative distrobox container definitions |
| `nix/dotfiles/starship.toml` | Gruvbox dark powerline prompt theme (verbatim TOML) |
| `ansible.yml` | System-level packages (requires `--ask-become-pass`) |
| `bootstrap.sh` | One-shot: install Nix + activate Home Manager |
| `migrate.sh` | Safe migration: verify Nix → remove old duplicates |
| `update.sh` | Update all package managers in one pass |
