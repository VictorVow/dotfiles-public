# Determinate Nix vs Upstream Nix

This repo uses Determinate Nix (via `bootstrap.sh`). This document explains what that means, how it compares to upstream Nix, and how to switch between the two if needed.

## What is Determinate Nix?

Determinate Nix is a downstream distribution of upstream Nix maintained by [Determinate Systems](https://determinate.systems/). It is not a fork — it is the same Nix software with additional patches applied on top, then validated and shipped as a separate release. Every Nix configuration, flake, or package that works on upstream Nix works identically on Determinate Nix.

The distinction matters mostly at the installer and defaults level. Determinate Nix enables modern features by default, ships performance improvements that have not yet landed upstream, and provides a clean uninstallation path via a receipt file. Upstream Nix is the NixOS Foundation's reference distribution, more conservative in its defaults.

As of early 2026, the Determinate Systems installer (`install.determinate.systems/nix`) exclusively installs Determinate Nix. It no longer offers an option to install upstream Nix. The NixOS community maintains a separate experimental installer (`github.com/NixOS/nix-installer`) for those who need upstream Nix specifically.

## Comparison

| | Determinate Nix | Upstream Nix |
|---|---|---|
| **Installer** | `install.determinate.systems/nix` | `nixos.org/download` or `github.com/NixOS/nix-installer` (experimental) |
| **Flakes** | Enabled by default | Experimental flag required |
| **`nix-command` CLI** | Enabled by default | Experimental flag required |
| **Parallel evaluation** | Yes (3-5x speedup) | No (single-threaded) |
| **Lazy trees** | Yes (20x disk reduction for large flakes) | No |
| **Flake registry** | Embedded in binary (resilient to GitHub outages) | Fetched from GitHub |
| **Uninstall** | `/nix/nix-installer uninstall` (receipt-based) | Manual process |
| **Security validation** | SOC 2 Type II on every release | Community-maintained |
| **Governance** | Determinate Systems (private company) | NixOS Foundation |
| **Compatibility with upstream** | 100% — all nixpkgs, flakes, Home Manager work identically | Baseline |
| **Versioning** | Own scheme (e.g. v3.x) layered on top of upstream Nix | Direct (e.g. 2.x) |

## Key Differences

### Flakes and `nix-command` enabled by default

Upstream Nix ships flakes and the unified `nix` CLI as experimental features. Using them requires adding `experimental-features = nix-command flakes` to `nix.conf`. Determinate Nix enables both by default. Since this repo is entirely flake-based, this is one of the main practical reasons for using Determinate Nix.

### Performance: parallel evaluation and lazy trees

Upstream Nix evaluates Nix expressions single-threaded. Determinate Nix adds multi-threaded parallel evaluation, typically 3-5x faster for large flakes on multi-core machines.

Lazy trees change how flake inputs are handled. Upstream Nix copies entire flake inputs to the Nix store upfront. Determinate Nix uses virtual filesystems to copy only what is actually needed. For a large flake input, this can reduce wall time by 3x and disk usage by 20x or more.

### `/nix/receipt.json`

The Determinate Systems installer writes a receipt to `/nix/receipt.json` that records every action taken during installation. This enables:

- Clean uninstallation in a single command (`/nix/nix-installer uninstall`)
- Automatic rollback if installation fails mid-process
- Auditable record of what the installer changed

Upstream Nix's traditional installer has no equivalent — uninstalling requires manually reversing changes.

### Embedded flake registry

Determinate Nix mirrors the upstream flake registry inside the binary itself (as of v3.13.2). `nixpkgs` and other registry entries resolve without a network request to GitHub. Upstream Nix fetches the registry from GitHub, meaning a GitHub outage can break `nix shell nixpkgs#…` and similar commands even when your packages are already cached locally.

### Versioning

Determinate Nix uses its own version numbering (v3.x at time of writing) applied on top of an upstream Nix base. Determinate Nix v3.17, for example, is based on upstream Nix 2.18 with additional patches. The two version numbers are not aligned — check `nix --version` output to identify which you have installed.

```
# Determinate Nix output looks like:
nix (Determinate Nix 3.17.1) 2.18.0

# Upstream Nix output looks like:
nix (Nix) 2.24.9
```

## Timeline

**November 10, 2025:** The Determinate Systems installer switched to installing Determinate Nix by default. The `--prefer-upstream-nix` flag was available as an opt-out.

**January 1, 2026:** The `--prefer-upstream-nix` flag was removed. The Determinate Systems installer no longer offers upstream Nix.

**Community response:** The NixOS Installer Working Group published an experimental fork (`github.com/NixOS/nix-installer`) that installs upstream Nix using the same receipt-based approach as the Determinate installer. It is community-maintained and foundation-owned but still experimental.

## Migration: Upstream Nix → Determinate Nix

This is non-destructive. Your existing Nix store, flake configurations, and Home Manager generations are all preserved.

**Check what you currently have:**

```bash
nix --version
# Contains "Determinate Nix" → already on Determinate Nix, nothing to do
# Contains only "Nix" → you have upstream Nix
```

**Migrate:**

```bash
# Uninstall upstream Nix first if you used the community installer
/nix/nix-installer uninstall   # only if /nix/nix-installer exists

# Or uninstall via the old script method (upstream multi-user):
# sudo /nix/nix-installl uninstall  # adjust to your installer's uninstall docs

# Install Determinate Nix
curl --proto '=https' --tlsv1.2 -sSf https://install.determinate.systems/nix \
  | sh -s -- install

# Re-activate your Home Manager configuration
cd ~/Documents/ESSENTIALS/installs
./bootstrap.sh
```

If your upstream Nix had `experimental-features = nix-command flakes` in `nix.conf`, you can remove that line — Determinate Nix enables both by default.

**Nothing else to change.** Your `flake.nix`, `home.nix`, and all modules are compatible as-is.

## Migration: Determinate Nix → Upstream Nix

Use this path if you want to return to the NixOS Foundation's reference distribution, for example to avoid the corporate dependency or to run an unmodified Nix binary.

**Step 1: Uninstall Determinate Nix**

```bash
/nix/nix-installer uninstall
```

This uses the receipt at `/nix/receipt.json` to cleanly reverse the installation. Your home directory and Nix configurations are not touched — only the Nix daemon and store infrastructure are removed.

**Step 2: Install upstream Nix**

Option A — NixOS community experimental installer (receipt-based, clean uninstall):

```bash
curl --proto '=https' --tlsv1.2 -sSf \
  https://install.lix.systems/lix \   # or check github.com/NixOS/nix-installer for current URL
  | sh -s -- install
```

> Note: Check `github.com/NixOS/nix-installer` for the current recommended install URL — this project is early and the URL may change.

Option B — Official upstream Nix multi-user install (traditional):

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

**Step 3: Re-enable experimental features**

Upstream Nix requires explicit opt-in for flakes and the `nix` CLI. Add this to `~/.config/nix/nix.conf` (create it if it doesn't exist):

```
experimental-features = nix-command flakes
```

Without this, `nix flake`, `nix run`, and `nix shell` commands will not work — and this repo's `bootstrap.sh` and Home Manager configuration all depend on them.

**Step 4: Re-activate Home Manager**

```bash
cd ~/Documents/ESSENTIALS/installs
./bootstrap.sh
```

**Note on performance:** You will lose parallel evaluation and lazy trees after switching to upstream. For large flakes or slow hardware this can be noticeable. If performance matters, consider staying on Determinate Nix.

## Which to use

This project uses Determinate Nix. The reasons:

- `bootstrap.sh` does not need to manually enable flakes — they work out of the box
- Faster evaluation on large flakes (the nixpkgs input is large)
- Clean uninstall via receipt if something goes wrong
- `nix --version` clearly identifies the distribution, making troubleshooting easier

Switch to upstream Nix if:

- You want Nix governed purely by the NixOS Foundation with no corporate involvement
- You need to reproduce an environment that explicitly excludes Determinate patches
- You are contributing to upstream Nix and need to test against the reference binary

For everyday desktop use on this machine, Determinate Nix is the right choice. All the trade-offs are in favour of it unless the governance concern is a priority for you.
