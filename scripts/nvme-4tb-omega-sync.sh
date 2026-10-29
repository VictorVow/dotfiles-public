#!/usr/bin/env bash
# nvme-4tb-omega-sync.sh: mirror /home onto the external 4TB-OMEGA drive.
#
# Excludes are regenerable data only (caches, package stores, re-downloadable
# game installs/models, search indexes, Trash). Paths are anchored to /home/.
# Extra args pass through to rsync, e.g. `nvme-4tb-omega-sync.sh --dry-run`.
#
# -x (--one-file-system) stops rsync descending into mounts under /home, most
# importantly the decrypted gocryptfs vaults in ~/Vaults: their encrypted
# copies (~/.local/share/plasma-vault/*.enc) are what gets backed up.
set -euo pipefail

dest=/run/media/boss/4TB-OMEGA
# Without this guard an unmounted drive means rsync fills the root disk.
mountpoint -q "$dest" || { echo "$dest is not mounted" >&2; exit 1; }

excludes=(
  /linuxbrew/

  # Generic caches
  /boss/.cache/
  /boss/.opencode1/cache/
  /boss/.var/app/*/cache/
  /boss/.local/share/Trash/
  /boss/.local/share/baloo/
  /boss/.stremio-server/stremio-cache/

  # Package / toolchain stores (re-downloadable)
  /boss/.npm/
  /boss/.bun/install/cache/
  /boss/.local/share/pnpm/
  /boss/.local/share/gradle/
  /boss/.local/share/go/
  /boss/.local/share/rustup/
  /boss/.rustup/
  /boss/.m2/repository/
  /boss/.pub-cache/
  /boss/.local/share/android/build-cache/
  /boss/.local/share/android/cache/

  # Re-downloadable apps, games and models (Proton saves in compatdata are kept)
  /boss/.local/share/flatpak/
  /boss/.local/share/Steam/steamapps/common/
  /boss/.local/share/Steam/steamapps/shadercache/
  /boss/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/
  /boss/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/shadercache/
  /boss/Games/SteamLibrary*/steamapps/common/
  /boss/Games/SteamLibrary*/steamapps/shadercache/
  /boss/.ollama/models/

  # Rebuildable index (cass)
  /boss/.local/share/coding-agent-search/
)

sudo rsync -avx --info=progress2 --delete --delete-excluded "${excludes[@]/#/--exclude=}" "$@" /home/ "$dest/home"
