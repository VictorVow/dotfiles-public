# System-Manager Migration Plan — Option A (Separate Flake)

## Context

Several system-level configs on this Kubuntu machine are currently edited by hand and untracked:
- `/etc/logiops.yml` — Logitech device customisation (logiops)
- `/etc/docker/daemon.json` — Docker daemon settings (if customised)
- systemd unit overrides for apt-installed services (earlyoom, logiops, vnstat, etc.)

The goal is to bring these under declarative, version-controlled management using `numtide/system-manager` without disrupting the existing Home Manager setup. Option A keeps system-manager in its own isolated flake (`nix/system-manager/`) so any upstream breakage cannot block `home-manager switch`.

---

## Files to Create

### `nix/system-manager/flake.nix`
```nix
{
  description = "system-manager configuration for boss's Kubuntu system";

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

### `nix/system-manager/modules/system.nix`
Top-level module that imports the three sub-modules and sets nixpkgs config:
```nix
{ pkgs, ... }: {
  nixpkgs.hostPlatform = "x86_64-linux";

  imports = [
    ./etc.nix
    ./services.nix
    ./tmpfiles.nix
  ];
}
```

### `nix/system-manager/modules/etc.nix`
Tracks `/etc` files currently edited by hand:
```nix
{ pkgs, ... }: {
  environment.etc = {

    # Logitech device customisation for logiops (MX Master series etc.)
    # Source: copy /etc/logiops.yml here as nix/system-manager/files/logiops.yml
    "logiops.yml" = {
      source = ../files/logiops.yml;
      mode = "0644";
    };

    # Docker daemon config — add only if /etc/docker/daemon.json is customised
    # "docker/daemon.json" = {
    #   source = ../files/docker-daemon.json;
    #   mode = "0644";
    # };
  };
}
```

### `nix/system-manager/modules/services.nix`
Drop-in overrides for apt-installed systemd services:
```nix
{ pkgs, ... }: {
  systemd.services = {

    # earlyoom — tighten thresholds (default 10%/5% RAM)
    # earlyoom = {
    #   serviceConfig = {
    #     ExecStart = lib.mkForce "${pkgs.earlyoom}/bin/earlyoom -m 5 -s 3 -r 60";
    #   };
    # };

    # logiops — ensure restart on failure
    logiops = {
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

  };
}
```

### `nix/system-manager/modules/tmpfiles.nix`
Runtime directory provisioning:
```nix
{ pkgs, ... }: {
  systemd.tmpfiles.rules = [
    # Add rules here as needed, e.g.:
    # "d /var/lib/custom-service 0755 root root -"
  ];
}
```

### `nix/system-manager/files/logiops.yml` *(must be populated before first apply)*
Copy the current system file:
```bash
sudo cp /etc/logiops.yml nix/system-manager/files/logiops.yml
```

---

## Files to Modify

### `update.sh`
Add a system-manager step **after** the Home Manager step (step 1), before apt (step 2).

Find the block ending the Home Manager step and insert after it:
```bash
# --- Step 1b: system-manager ---
log_step "system-manager"
if sudo nix run 'nix/system-manager#system-manager' -- switch --flake 'nix/system-manager#default'; then
    log_ok "system-manager"
else
    log_fail "system-manager"
    FAILED=true
fi
```

The `--no-nix` flag should also skip the system-manager flake update if the user adds it to scope (optional extension).

### `docs/daily-workflow.md`
Add a **System-manager** section covering:
- How to apply changes: `sudo nix run 'nix/system-manager#system-manager' -- switch --flake 'nix/system-manager#default'`
- How to add a new `/etc` file: add entry in `etc.nix`, put source file in `files/`
- How to roll back: `sudo nix run 'nix/system-manager#system-manager' -- rollback`
- Note: only run from repo root (relative flake path)

### `README.md`
Add a **system-manager** setup step after the "Run ansible" step in the quick-start section:
```
5. Apply system-manager (first time):
   sudo nix run github:numtide/system-manager -- switch --flake ./nix/system-manager#default
```

### `docs/architecture.md`
Update the four-layer table to mention system-manager as a fifth layer for `/etc` + systemd unit overrides.

---

## New Directory Layout

```
nix/system-manager/
├── flake.nix
├── flake.lock              (auto-generated on first run)
├── files/
│   └── logiops.yml         (copied from /etc/logiops.yml before first apply)
└── modules/
    ├── system.nix
    ├── etc.nix
    ├── services.nix
    └── tmpfiles.nix
```

---

## Step-by-Step Execution Order

1. **Copy current `/etc/logiops.yml`** into `nix/system-manager/files/logiops.yml`
   - `sudo cat /etc/logiops.yml > nix/system-manager/files/logiops.yml`
2. **Create all files** as described above
3. **First apply** (generates `flake.lock`):
   ```bash
   cd ~/Documents/ESSENTIALS/installs
   sudo nix run github:numtide/system-manager -- switch --flake ./nix/system-manager#default
   ```
4. **Verify** logiops.yml is now a symlink into the Nix store:
   ```bash
   ls -la /etc/logiops.yml
   # should point to /run/system-manager/...
   sudo systemctl restart logiops
   sudo systemctl status logiops
   ```
5. **Update `update.sh`** and **docs** as described above
6. **Commit** everything: `git add nix/system-manager/ && git commit -m "add: system-manager separate flake (Option A)"`

---

## Verification

| Check | Command |
|-------|---------|
| `/etc/logiops.yml` tracked | `ls -la /etc/logiops.yml` — should be symlink to Nix store |
| logiops service running | `sudo systemctl status logiops` |
| Rollback works | `sudo nix run 'nix/system-manager#system-manager' -- list-generations` |
| update.sh still works end-to-end | `./update.sh --dry-run` |
| Home Manager unaffected | `hms` still applies without errors |
| Second apply is idempotent | Run apply twice, second run reports no changes |

---

## Key Caveats to Keep in Mind

- Run apply commands from the repo root (`~/Documents/ESSENTIALS/installs`) — the flake path `nix/system-manager` is relative.
- `sudo` must have Nix in PATH — Determinate Nix handles this, but verify with `sudo nix --version`.
- system-manager is **alpha**: pin to a specific commit/tag in `flake.nix` once stable behaviour is confirmed.
- `/etc/logiops.yml` will become a symlink owned by the Nix store — don't edit it directly after migration; edit `files/logiops.yml` and re-apply.
- Single active configuration rule: never apply two different flake paths; always apply from the same path.
- `environment.systemPackages` in system-manager installs Nix packages to `/run/system-manager/sw` — not needed here unless apt packages need Nix replacements.
