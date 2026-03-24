# Migration Guide

How to migrate from an existing apt/Homebrew/pipx/npm setup to the Nix-based configuration.

## Overview

`migrate.sh` handles the migration safely:
1. Verifies that all Nix packages are working **before removing anything**
2. Removes the now-duplicate packages from apt, pipx, npm, and Homebrew
3. Is idempotent — safe to re-run after partial failures

## Before You Start

Make sure `bootstrap.sh` has already been run and `home-manager switch` succeeded:

```bash
# Check that key binaries are in the Nix profile
ls ~/.nix-profile/bin/ | grep -E "git|tmux|btop|nvim|starship"

# Check Home Manager has at least one generation
home-manager generations
```

If any of these fail, run `./bootstrap.sh` first.

## Dry Run First

Always preview before committing:

```bash
./migrate.sh --dry-run
```

This shows exactly what would be removed without touching anything.

## Running the Migration

```bash
./migrate.sh
```

### What it checks (verification gate)

The script verifies all of these before removing anything. If any check fails, it aborts without removing anything:

**Binaries that must exist in `~/.nix-profile/bin/`:**
- git, tmux, btop, nvim, starship, yt-dlp, deno, rclone, gh
- distrobox, ffmpeg, scrcpy, streamlink, signal-desktop

**Other checks:**
- `home-manager generations` returns at least one generation
- Distrobox containers `dev` and `media` exist

### What it removes (if all checks pass)

**From apt:**
- btop, distrobox, git, gh, tmux, neovim, starship, ffmpeg, yt-dlp, scrcpy, signal-desktop, streamlink, sniffnet, rclone, syncthing, jackett, solaar, virt-manager, pavucontrol

**From pipx:**
- yt-dlp, poetry, uv

**From npm globals:**
- deno, typescript, corepack

**From Homebrew:**
- neovim, starship, scrcpy, jackett, zrok, clojure, dotnet, ruby, sniffnet, gh

## After the Migration

### Remove the old Home Manager channel config

The old `~/.config/home-manager/home.nix` (a channels-based 3-package config) is superseded by the flake in `nix/`. Remove it to avoid confusion:

```bash
rm -rf ~/.config/home-manager/
```

The flake-based Home Manager doesn't use this directory.

### Clean up Nix channels

```bash
# List channels
nix-channel --list

# Remove the old home-manager channel if present
nix-channel --remove home-manager
```

### Verify the result

```bash
# All key tools should come from ~/.nix-profile
which git tmux nvim starship yt-dlp

# Shell environment
echo $GOPATH $ANDROID_HOME $PODMAN_USERNS

# Starship prompt loads correctly
starship explain

# Git config is correct
git config --list | grep -E "user\.|credential\.|signing"

# Distrobox containers are present
distrobox list
```

## Recovery

If the migration script aborts at the verification gate, nothing has been removed. Fix the issue and re-run.

If the script succeeds but something doesn't work:

```bash
# Roll back Home Manager to the previous generation
home-manager generations
home-manager switch --switch-generation <N>

# Reinstall a missing apt package temporarily
sudo apt install <package>
```

If Nix itself is broken, the Determinate Systems installer supports repair:

```bash
/nix/nix-installer repair
```

## What Is NOT Migrated

Some tools stay in their current locations. See [limitations.md](limitations.md) for the full list.
