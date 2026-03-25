# system-manager

> **Decision:** Not worth changing currently, it's alpha quality and modifies too little.

[`numtide/system-manager`](https://github.com/numtide/system-manager) is an alpha-quality Nix-based tool for managing system-level state on non-NixOS Linux. It brings NixOS-style declarative configuration (atomic apply, generation tracking, rollback) to Ubuntu and other systemd-based distributions, without replacing the OS.

---

## What it manages

system-manager deliberately scopes itself to a small surface area to avoid conflicting with the distro:

| Module | What it controls |
|--------|-----------------|
| `environment.etc` | Files under `/etc` — content, ownership, mode |
| `systemd.services` / `.timers` / `.sockets` / `.targets` / `.mounts` | Systemd unit declarations and drop-in overrides |
| `systemd.maskedUnits` | Disable distro-shipped units by symlinking to `/dev/null` |
| `environment.systemPackages` | Nix packages installed to `/run/system-manager/sw`, exported via `/etc/profile.d/` |
| `systemd.tmpfiles` | tmpfiles.d(5) rules for runtime directories and permissions |
| `systemd.globalEnvironment` | Environment variables injected into all systemd units |
| `users.users` (opt-in, via userborn) | User and group provisioning |

It does **not** manage: kernel, bootloader, apt packages, Flatpak, init system, partition layout.

### How it works

```
nix run github:numtide/system-manager -- switch --flake .#default
```

- Builds the configuration as a Nix derivation (errors caught at build time, not apply time)
- Atomically applies changes to `/etc` and systemd units
- Writes a state file (similar to Terraform) to support rollback to previous generations
- Requires root (`sudo`) to modify system paths

---

## What it could manage in this repo

### High-value targets

**`/etc/logiops.yml`** — Logitech device button/scroll/gesture customisation for logiops. Currently not tracked anywhere. This is the clearest win: one `environment.etc."logiops.yml".source` declaration puts it under version control and applies it atomically.

**`/etc/docker/daemon.json`** — Any Docker daemon customisation (log driver, storage driver, insecure registries, default address pool). Currently any edits are made manually and untracked.

**systemd unit overrides** — Services installed by apt (earlyoom, logiops, vnstat, power-profiles-daemon, postfix) ship with default unit files. If you want to customise restart policy, resource limits, environment, or timeouts, `systemd.services.<name>` drop-ins let you declare those overrides rather than editing files in `/etc/systemd/system/` by hand.

**System-wide environment** — Anything that needs to be in `/etc/profile.d/` for all users/login shells (not just the Home Manager user session).

**tmpfiles rules** — Creating `/var/` directories for custom services, setting permissions on device nodes, cleaning up temp paths on boot.

### What it cannot replace in this setup

| Current tool | Why system-manager cannot replace it |
|-------------|--------------------------------------|
| Ansible (apt packages) | system-manager only installs Nix packages; it cannot install apt packages. KDE essentials, system libs, earlyoom, logiops, Docker, Mullvad, etc. must remain in Ansible / 3rd-party scripts. |
| `docker.sh` / `mullvad-vpn.sh` | 3rd-party apt repo + GPG key setup is outside system-manager scope |
| `flatpak.sh` | Flatpak is entirely separate from Nix |
| `arkenfox.sh` | User-space; belongs in Home Manager if ever declarativised |
| KDE Plasma settings | User-space; `plasma-manager` is the right tool |
| Distrobox container internals | Runtime state inside containers |

---

## Relationship to Ansible

system-manager is **not a drop-in Ansible replacement** for this repo. Ansible installs apt packages that have no Nix equivalents; system-manager cannot touch those. The split would be:

- **Ansible** continues to own: apt package installation, 3rd-party apt repo setup, running `3rd-party-packages/` scripts
- **system-manager** takes over: `/etc` config files currently edited by hand, systemd unit customisations, any system packages that could be served by Nix instead of apt

---

## Integration outline

### Option A: Separate flake (recommended for alpha software)

Keep system-manager isolated from the existing `nix/flake.nix` so its lockfile churn and potential breakage don't affect Home Manager.

**New files:**

```
nix/system-manager/
├── flake.nix              # Inputs: nixpkgs + system-manager; output: systemConfigs.default
├── flake.lock             # (auto-generated on first run)
└── modules/
    ├── system.nix         # Top-level: nixpkgs config, imports all modules below
    ├── etc.nix            # environment.etc declarations (/etc/logiops.yml, etc.)
    ├── services.nix       # systemd.services drop-ins for earlyoom, logiops, vnstat, etc.
    └── tmpfiles.nix       # systemd.tmpfiles rules for runtime directories
```

Minimal `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, system-manager, ... }: {
    systemConfigs.default = system-manager.lib.makeSystemConfig {
      modules = [ ./modules/system.nix ];
    };
  };
}
```

Apply with:

```
sudo nix run 'nix/system-manager#system-manager' -- switch --flake nix/system-manager#default
```

### Option B: Extend existing `nix/flake.nix`

Add a `systemConfigs` output alongside the existing `homeConfigurations` output. One lockfile for everything, but system-manager breakage could block `home-manager switch`.

**Modified files:**
- `nix/flake.nix` — add `system-manager` input and `systemConfigs.default` output
- `nix/home.nix` — no changes needed

### Files modified in both options

| File | Change |
|------|--------|
| `update.sh` | Add `sudo nix run ... -- switch` step alongside `hms` |
| `docs/daily-workflow.md` | Add system-manager switch to the daily update section |
| `README.md` | Add system-manager setup step after bootstrap |

---

## Key caveats

- **Alpha software.** The API may change between versions. Pin the input to a specific commit/tag in production.
- **Requires Nix 2.32+.** Determinate Nix (used by `bootstrap.sh`) satisfies this.
- **sudo PATH.** When running with `sudo`, the Nix profile must be in PATH. Determinate Nix handles this, but it's worth verifying after install.
- **Ubuntu officially supported.** Kubuntu is Ubuntu under the hood and should work without `allowAnyDistro = true`.
- **Does not install apt packages.** `environment.systemPackages` installs from Nix/nixpkgs only. Ansible remains required for the apt layer.
- **Single active configuration.** system-manager treats a second flake applied from a different path as "uninstall previous state". Keep all configuration in one place.
