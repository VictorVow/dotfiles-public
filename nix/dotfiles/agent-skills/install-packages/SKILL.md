---
name: install-packages
description: Install or remove a package/tool on this system — decide which of the repo's package managers owns it (Nix/Home Manager, Ansible, Brew, uv, npm, AppMan, Flatpak) and where to add it. Use whenever the user asks to install, add, remove or update software on boss-laptop or lord-ubuntu, or asks "how do I get X on this system". Applies only inside the installs repo (~/Projects/installs).
---

# Installing packages on this system

The system uses several package managers in layers. Pick the right one, edit its manifest, then apply. Full rationale: `docs/system/architecture.md`; the gap each layer covers: `docs/system/packages.md`; what can't go in Nix: `docs/system/limitations.md`; add/remove/update mechanics: `docs/system/daily-workflow.md`.

## Decision tree

Work top-down; stop at the first layer that can own the package.

1. **System-level need?** (daemon/service, kernel module, sudo install, apt-only, KDE/portal/system integration)
   → `ansible.yml` for system packages; `custom-installers.yml` + a new `ansible/installers/<tool>.yml` for third-party tools with their own installer (pattern: Docker, Tailscale, Mullvad). Comment header of `nix/modules/packages.nix` lists the known can't-be-Nix cases.

2. **Check the AI-agent flake first if it's an agent/LLM tool.** `nix/modules/packages.nix` exposes `llmAgents.<name>` (numtide llm-agents.nix, has its own binary cache). List available: `nix eval --json 'github:numtide/llm-agents.nix#packages.x86_64-linux' --apply 'builtins.attrNames'` — do this BEFORE hand-rolling a derivation; common agents (opencode, cursor-agent, hermes-desktop, …) are already packaged there.

3. **In nixpkgs?** (`nsp <name>`)
   → `nix/modules/packages.nix` `home.packages` under its existing section header (desktop / user `boss`). Headless-server tools for lord-ubuntu → `nix/modules/packages-server.nix`.
   - Config-bearing apps → a `programs.*` module instead: shell/CLI in `nix/modules/shell-apps.nix`, GUI in `gui-apps.nix`, editors in `editors.nix`, AI agents in `ai-agents.nix` (server variant `ai-agents-server.nix`).
   - Use `pkgs-unstable.<name>` for packages needing fresher versions, `pkgs-latest.<name>` for attrs only in the newest pin — match the surrounding entries' convention.

4. **Not in nixpkgs / nixpkgs lags** → pick by ecosystem, one manifest each:
   - Python CLI → `uv-tools.txt`
   - Node CLI → `npm-globals.txt`
   - General CLI/casks (Linuxbrew) → `Brewfile` (desktop), `Brewfile.lord` (server)
   - AppImage → `appman-appimages.txt`
   - GUI desktop app → `flatpak.md` / `flatpak.sh`
   - Prebuilt binary/tarball with no better home → a small `mkDerivation`/`fetchurl` in the let-block of `packages.nix` (pattern: `herdrApp`) — last resort, prefer the manifests above.

5. **Project-scoped tool, not a system package?** → it belongs in that repo's dev environment (see `direnv-deploy` skill), not here.

## After editing

- Desktop: `hms` (home-manager switch). Then `update.sh`/`update-all` refreshes brew/uv/npm/AppMan/Flatpak lists on its schedule.
- Rollback: `home-manager generations` → `switch --switch-generation N`.
- When adding to a manifest, match the file's existing style: section headers, `nixpkgs` annotation comments explaining why a package isn't in Nix, and `# which <binary>` hints where the attr name differs from the binary.
