# Overview

System configuration for Kubuntu (KDE Plasma on Ubuntu). Manages packages, dotfiles, shell environment, and development containers through a layered approach: **Nix + Home Manager** handles user-space, **Ansible** handles system-level packages.

## Repo Structure

Note: High-level view with not every file/directory is listed, only the most important ones.

```
installs/
├── bootstrap.sh              # Install Nix + activate Home Manager on a fresh system
├── update.sh                 # Update all package managers in one pass
├── update.d/                 # update.sh's sourced pieces: lib.sh helpers + one NN-<manager>.sh per step
├── ansible.yml               # System-level packages (requires sudo)
├── custom-installers.yml     # 3rd-party tools (Docker, Tailscale, Mullvad, Homebrew, AppMan, etc.) — imported by ansible.yml
├── ansible/installers/       # One task file per 3rd-party tool, imported by custom-installers.yml
│   └── lord-ubuntu.yml       # User-level setup for lord-ubuntu (brew + Brewfile.lord) — separate playbook, over SSH
├── ansible.cfg               # Ansible settings (explicit inventory, no fact injection) — picked up when run from repo root
├── inventory.ini             # Explicit localhost inventory for the playbooks
├── flatpak.sh                # Set up Flatpak + reinstall Flatpak apps
├── flatpak.md                # List of installed Flatpak apps
├── Brewfile                  # Homebrew packages (Linuxbrew) — desktop
├── Brewfile.lord             # Server-scoped brew list (cass) for lord-ubuntu
├── appman-appimages.txt      # AppImages managed by AppMan
├── arkenfox.sh               # Apply/update arkenfox user.js on a Firefox profile
├── CHANGELOG.md              # Dated log of workflow-affecting changes (here + Self-Hosted repos) — written by the system-update-changelog skill
├── CVLOG.md                  # Skills/experience list grouped by skill, each item dated + backlinked (commit, Logseq block, agent session) — CV/resume reference, written by the system-update-cvlog skill
├── uv-tools.txt              # Python CLI tools managed by `uv tool` (not in / lagging in nixpkgs) — installed by update.sh
├── npm-globals.txt           # Global npm CLIs (not in nixpkgs/llm-agents) — installed by the shell.nix activation, upgraded by update.sh
├── .sops.yaml                # sops creation rules (age recipient for nix/secrets/*)
├── nix/                      # Home Manager flake — all user-space config
│   ├── flake.nix             # Flake inputs (nixpkgs-unstable + home-manager + sops-nix)
│   ├── home.nix              # Top-level Home Manager config (desktop, user `boss`), imports modules
│   ├── home-lord.nix         # Headless-server Home Manager config (lord-ubuntu, user `lord`), imports *-server.nix + shared modules
│   ├── secrets/              # sops-encrypted (age) secrets, safe to commit
│   │   └── rclone.yaml       # rclone remote credentials (decrypted at activation)
│   ├── dotfiles/             # Verbatim config files managed via home.file
│   │   ├── starship.toml     # Gruvbox dark powerline prompt theme
│   │   ├── backups/          # vorta-excludes.txt: Vorta raw exclusions, written into settings.db by desktop.nix; nvme-4tb-omega-sync.sh: rsync /home to the external 4TB-OMEGA drive, skipping external-drive-excludes.txt
│   │   ├── claude-hooks/     # Claude Code hook scripts (bash-secret-guard.py)
│   │   ├── claude-statusline/ # Claude Code statusline.py (deployed by ai-agents.nix)
│   │   └── agent-skills/    # Own skills in the Agent Skills spec format (agentskills.io), one folder per skill (SKILL.md + helpers); auto-linked by agent-skills.nix
│   └── modules/
│       ├── packages.nix      # All home.packages (replaces apt/brew/pipx/npm lists) — desktop
│       ├── packages-server.nix # Headless subset of packages.nix for lord-ubuntu
│       ├── shell-apps.nix    # programs.* for shell/CLI apps: git, tmux, starship, htop, gh, direnv, ssh
│       ├── ai-agents.nix     # Claude Code (settings, statusline, hooks), Codex, OpenCode (+ `opencode1` w/ magpie Devin/Cursor plugins), shared MCP server registry
│       ├── ai-agents-server.nix # Server variant of ai-agents.nix (no browser MCPs)
│       ├── ai-secrets.nix    # sops-encrypted AI provider keys (nix/secrets/ai.yaml)
│       ├── editors.nix       # Neovim, micro, VS Code/VSCodium settings, MarkText
│       ├── agent-skills.nix # Agent Skills spec skills: links dotfiles/agent-skills/* + Orca skills + logseq-cli (flake inputs) + ~/.agents/skills/ mirror
│       ├── firefox.nix       # programs.firefox: profiles, shared settings/search engines, cookie policy, profiles.ini fixup
│       ├── firefox-search.nix # Shared Firefox search engines (plain attrset imported by firefox.nix)
│       ├── desktop.nix       # Desktop integration: autostart entries (Solaar), Dolphin HTML thumbnailer, Vorta raw exclusions
│       ├── services.nix      # systemd user services (Ollama, Jackett)
│       ├── weekly-cleanup.nix # weekly Nix GC + Docker prune timer (shared by boss-laptop + lord-ubuntu)
│       ├── logseq-mirror-git.nix # hourly git commit of the logseq-apex Markdown mirror (readable graph history)
│       ├── update-all.nix    # update.sh timer: daily on boss-laptop, every 2 days on lord-ubuntu
│       ├── gpg-expiry.nix    # Desktop notification when a GPG key nears expiry
│       ├── gui-apps.nix      # programs.* for GUI apps: rofi, obs (Zed is AppMan-installed, config unmanaged)
│       ├── shell.nix         # Bash, PATH, env vars, aliases, npm AI CLI activation
│       ├── shell-server.nix  # Server variant of shell.nix (no GUI/Yakuake/Android bits)
│       ├── rclone.nix        # Declarative rclone remotes (programs.rclone + sops creds)
│       ├── cass.nix          # systemd user timers keeping the cass agent-session search index fresh (search-agent-history skill)
│       ├── recoll.nix        # services.recoll: full-text index of ~/Documents, ~/Downloads, ~/Media (searchable file types listed inside)
│       └── distrobox.nix     # Declarative distrobox containers (dev + media)
├── scripts/                  # Standalone helper/diagnostic scripts
│   ├── chromium-suid-sandbox.sh   # Fix SUID sandbox for Nix ungoogled-chromium + google-chrome
│   ├── html-thumbnailer.sh        # Dolphin/KIO HTML preview renderer (headless Chromium); deployed as a .thumbnailer by nix/modules/desktop.nix
│   ├── waydroid-init.sh           # One-shot Waydroid setup
│   ├── looking-glass/             # Win11 VM viewed via Looking Glass IDD: VM creation script + setup playbook (README)
│   ├── mailbox.org/mailbox-dns.sh # Apply mailbox.org MX/SPF/DKIM/DMARC records to the Namecheap-hosted domains
│   ├── nix-build-report.py        # Used by update.sh: which top-level packages were built locally (cache misses) + build times
│   ├── migration/                 # Disk migration runbook (README) + scripts: swap lord-ubuntu's root disk, optionally converting ext4 → btrfs
│   ├── network-debugging/         # Toolkit for LAN/mesh streaming diagnosis: per-segment latency, loss, iperf3 throughput matrix (README = playbook)
│   └── security/                  # gitleaks-based audit + in-place scrubbing of secrets leaked into agent transcripts (README = playbook)
├── 0SHORTCUTS/               # App shortcuts (.desktop/executables) scanned by vault-launch (rofi), outside XDG
│   ├── 0STARTUP/             # Login/startup scripts: yakuake1.sh orchestrator, sections/*.sh tmux panes, shutdown.sh
│   ├── 1COMMON/              # Everyday apps; subdirs become [Category] prefixes in vault-launch
│   └── 2OTHER/               # Miscellaneous apps (top level only scanned)
└── docs/                     # All documentation
    ├── archive/              # Previously relevant, only kept for historical purposes
    ├── system/               # Reference docs for this system's config (implemented, in use)
    │   ├── architecture.md   # How the layers fit together and why
    │   └── ...
    ├── research/             # Deep-dive research and comparison docs
    │   ├── git-worktrees.md
    │   ├── app-launchers.md
    │   ├── mesh-networks.md
    │   └── ...
    └── comparison-tables/    # Sortable/weightable comparison tables + their renderer
        ├── data/             # The table Markdown + per-table .weights.json sidecars
        └── browser-render/   # Render the tables as styled webpages (live-reload server + standalone HTML)

```



## Related Repos

- **Self-hosted services** — `~/Projects/Git/1MY_REPOS/Self-Hosted`: one repo per service (Headscale, Forgejo, Stremio, Calibre, DAV, RSS, Rclone, Dashboard, …), mostly deployed with Ansible to the home server `lord-ubuntu` and reachable tailnet-only at `*.device.example.com`. Its `README.md` is the repo map — a symlink to [docs/system/self-hosted-readme.md](docs/system/self-hosted-readme.md), kept here so it's tracked in git (relative links in it resolve from the Self-Hosted directory). This repo only holds the client side (e.g. `nix/modules/rclone.nix`, `docs/system/headscale.md`, `docs/system/nfs-mounts.md`).

## Quick Start

### Prerequisites

- Kubuntu / Ubuntu-based system
- `curl` (available by default)
- `git` (to clone this repo)
- Not running as root

### Fresh install (new machine)

```bash
# 1. Install Nix + activate Home Manager configuration
./bootstrap.sh          # desktop (./nix#boss); pass 'lord' on lord-ubuntu

# Run `exec bash` in every shell opened before the Nix install (tmux panes too), then:

# 2. Install system-level packages + 3rd-party tools (Docker, Tailscale, Mullvad, Homebrew, etc.)
ansible-playbook ansible.yml --ask-become-pass
```

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

- [Architecture](docs/system/architecture.md) — why multiple package managers coexist
- [Package inventory](docs/system/packages.md) — full list of what's managed where
- [Daily workflow](docs/system/daily-workflow.md) — adding packages, updating, rollbacks
- [Limitations](docs/system/limitations.md) — what can't go in Nix and alternatives
- [Migration to Nix](docs/archive/migration-to-nix.md) — archived: the completed apt/brew/pipx/npm → Nix migration
- [Nix secrets](docs/system/nix-secrets.md) — how sops-nix encrypts/decrypts secrets (rclone credentials, etc.)
- [lord-ubuntu Home Manager](docs/system/lord-ubuntu-home.md) — headless-server config (`./nix#lord`) sharing modules with the desktop
- [lord-ubuntu disk migration](scripts/migration/README.md) — runbook + scripts for swapping the root NVMe: live `pvmove` (ext4) or the scripted btrfs conversion (Path B, used 2026-10-27)
- [Adding a new host](docs/system/bootstrap-new-host.md) — repeatable checklist for bringing another machine into the flake
