#!/usr/bin/env bash
# nvme-4tb-omega-sync.sh: mirror /home onto the external 4TB-OMEGA drive.
#
# Excludes (external-drive-excludes.txt) are regenerable data only: caches,
# package stores, re-downloadable game installs/models, search indexes, Trash.
# Extra args pass through to rsync, e.g. `nvme-4tb-omega-sync.sh --dry-run`.
#
# -x (--one-file-system) stops rsync descending into mounts under /home, most
# importantly the decrypted gocryptfs vaults in ~/Vaults: their encrypted
# copies (~/.local/share/plasma-vault/*.enc) are what gets backed up.
set -euo pipefail

dest=/run/media/boss/4TB-OMEGA
# Without this guard an unmounted drive means rsync fills the root disk.
mountpoint -q "$dest" || { echo "$dest is not mounted" >&2; exit 1; }

# Regenerable-data excludes live next to this script.
excludes="$(dirname "$(readlink -f "$0")")/external-drive-excludes.txt"

sudo rsync -avx --info=progress2 --delete --delete-excluded --exclude-from="$excludes" "$@" /home/ "$dest/home"
