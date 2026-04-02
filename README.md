# Overview

System configuration for Kubuntu (KDE Plasma on Ubuntu). Manages packages, dotfiles, shell environment, and development containers through a layered approach: **Nix + Home Manager** handles user-space, **Ansible** handles system-level packages.

## Repo Structure

Note: High-level view with not every file/directory is listed, only the most important ones.

```
installs/
├── bootstrap.sh              # Install Nix + activate Home Manager on a fresh system
├── update.sh                 # Update all package managers in one pass
├── ansible.yml               # System-level packages (requires sudo)
├── flatpak.sh                # Set up Flatpak + reinstall Flatpak apps
├── 3rd-party-packages/       # Scripts for tools not in standard repos
│   ├── docker.sh
│   ├── mullvad-vpn.sh
│   ├── android-studio.sh
│   └── ...
├── nix/                      # Home Manager flake — all user-space config
│   ├── flake.nix             # Flake inputs (nixpkgs-unstable + home-manager)
│   ├── home.nix              # Top-level Home Manager config, imports modules
│   ├── dotfiles/             # Verbatim config files managed via home.file
│   │   ├── starship.toml     # Gruvbox dark powerline prompt theme
│   │   └── claude-hooks/     # Claude Code hook scripts (notify-waiting.sh, etc.)
│   └── modules/
│       ├── packages.nix      # All home.packages (replaces apt/brew/pipx/npm lists)
│       ├── programs.nix      # programs.* configs: git, tmux, starship, neovim, htop, claude-code
│       ├── shell.nix         # Bash, PATH, env vars, aliases, npm AI CLI activation
│       └── distrobox.nix     # Declarative distrobox containers (dev + media)
└── docs/                     # All documentation
    ├── archive/              # Previously relevant, only kept for historical purposes
    ├── system/               # Reference docs for this system's config (implemented, in use)
    │   ├── architecture.md   # How the layers fit together and why
    │   └── ...
    └── research/             # Deep-dive research and comparison docs
        ├── git-worktrees.md
        ├── app-launchers.md
        ├── mesh-networks.md
        └── ...

```



## Quick Start

### Prerequisites

- Kubuntu / Ubuntu-based system
- `curl` (available by default)
- `git` (to clone this repo)
- Not running as root

### Fresh install (new machine)

```bash
# 1. Install Nix + activate Home Manager configuration
./bootstrap.sh

# Open a new terminal, then:

# 2. Install system-level packages (KDE integration, services, Docker, etc.)
ansible-playbook ansible.yml --ask-become-pass

# 3. Run any 3rd-party installers you need (Docker, Mullvad, etc.)
./3rd-party-packages/docker.sh
./3rd-party-packages/mullvad-vpn.sh
```

### Migrating an existing system

If you already have the old apt/brew/pipx/npm setup:

```bash
# Dry-run first to preview what will be removed
./migrate.sh --dry-run

# Then run for real
./migrate.sh
```

`migrate.sh` verifies all Nix packages are present before removing anything. See [docs/migration.md](docs/migration.md) for details.

## Daily Use

| Task | Command |
|------|---------|
| Apply config changes | `hms` (alias for `home-manager switch`) |
| Update all packages | `update-all` (alias for `update.sh`) |
| Search for a package | `nsp <name>` → `nix search nixpkgs <name>` |
| Temporary shell with a package | `nsh <name>` → `nix shell nixpkgs#<name>` |
| Enter dev container | `dbe dev` |
| Enter media container | `dbe media` |
| Roll back Home Manager | `home-manager generations` → `home-manager switch --switch-generation <N>` |

## Further Reading

- [Architecture](docs/architecture.md) — why multiple package managers coexist
- [Package inventory](docs/packages.md) — full list of what's managed where
- [Daily workflow](docs/daily-workflow.md) — adding packages, updating, rollbacks
- [Migration guide](docs/migration.md) — migrating from apt/brew/pipx/npm
- [Limitations](docs/limitations.md) — what can't go in Nix and alternatives
