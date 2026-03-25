# Backup Systems

## Systems

### 1. External SSD
**Command:** `sudo rsync -avz --info=progress2 /home/ /media/boss/4TB-OMEGA/home --delete`
**Destination:** `/media/boss/4TB-OMEGA/home`
**Scope:** All of `/home/` (full mirror, with `--delete`)

---

### 2. Vorta (Borg)
**Binary:** `/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=vorta com.borgbase.Vorta`
**Config/data:** `~/.var/app/com.borgbase.Vorta/data/Vorta/settings.db`
**Cache:** `~/.var/app/com.borgbase.Vorta/cache/borg/`
**Destinations:** BorgBase.com, rsync.net, SSD-1TB-Transcend (3 repos)
**Scope:** `/home/boss` and `/media/veracrypt2`

---

### 3. rclone cloudsync
**Script:** `~/Vaults/gocryptfs1/0SHORTCUTS/0STARTUP/rclone-sync.sh cloudsync`
**Destination:** Backblaze B2 (`crypt_BackblazeB2_backblaze-rclone1:mount2-cloudsync/`) — encrypted via rclone crypt remote
**Frequency:** Loop: sleep 4h, sync, sleep 4d

---

### 4. rclone android-backups
**Script:** `~/Vaults/gocryptfs1/0SHORTCUTS/0STARTUP/rclone-sync.sh android-backups`
**Destination:** Backblaze B2 (`crypt_BackblazeB2_backblaze-rclone1:Android-Backups`) — encrypted
**Frequency:** Loop: sleep 1h, sync, sleep 3d

---

### 5. Syncthing
**Config:** `~/.config/syncthing/config.xml`
**Scope:** Bidirectional sync to/from Android phone and other devices (20 folders)

---

## Coverage Table

> **Note:** "External SSD" and "Vorta" cover all of `/home/boss/` (and Vorta also covers `/media/veracrypt2`), so they are checked for every row below.

| Path | External SSD | Vorta | rclone cloudsync | rclone android-backups | Syncthing |
|------|:---:|:---:|:---:|:---:|:---:|
| `/home/boss/` *(entire)* | ✓ | ✓ | | | |
| `/media/veracrypt2` | | ✓ | | | |
| `~/.config` | ✓ | ✓ | ✓ | | |
| `~/.cache` | ✓ | ✓ | ✓ | | |
| `~/.var/app` | ✓ | ✓ | ✓ | | |
| `~/.wine/drive_c` | ✓ | ✓ | ✓ | | |
| `~/.local/share/Steam` | ✓ | ✓ | ✓ | | |
| `~/.local/share/lutris` | ✓ | ✓ | ✓ | | |
| `~/Games/Adult` | ✓ | ✓ | ✓ | | |
| `~/Games/itchio-games` | ✓ | ✓ | ✓ | | |
| `~/Games/Pirated` | ✓ | ✓ | ✓ | | |
| `~/Games/1Git` | ✓ | ✓ | ✓ | | |
| `~/Downloads/VideoDownloader` | ✓ | ✓ | ✓ | | |
| `~/Downloads/1NEWMUSIC` | ✓ | ✓ | | | ✓ |
| `~/Vaults/gocryptfs2` | ✓ | ✓ | ✓ | | |
| `~/Vaults/gocryptfs1/Thunderbird` | ✓ | ✓ | ✓ | | |
| `~/Vaults/gocryptfs1/Android-sync/Android-Backups` | ✓ | ✓ | | ✓ | |
| `~/Vaults/gocryptfs1/Android-sync/Android-Backups/Android-NeoBackup` | ✓ | ✓ | | ✓ | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-Backups/Android-Signal` | ✓ | ✓ | | ✓ | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-Backups/Android-SeedVault` | ✓ | ✓ | | ✓ | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-WhatsApp` | ✓ | ✓ | | | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-WhatsApp1` | ✓ | ✓ | | | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-NewPipe` | ✓ | ✓ | ✓ | | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-Documents` | ✓ | ✓ | | | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-CORE` | ✓ | ✓ | | | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-MP` | ✓ | ✓ | | | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-Music` | ✓ | ✓ | | | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-DCIM` | ✓ | ✓ | | | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-AnkiDroid` | ✓ | ✓ | | | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-1` | ✓ | ✓ | | | ✓ |
| `~/Vaults/gocryptfs1/Android-sync/Android-2` | ✓ | ✓ | | | ✓ |
| `~/Videos/Syncthing/BAE-PINK2-Logseq` | ✓ | ✓ | | | ✓ |
| `~/Videos/Syncthing/Shadow2` | ✓ | ✓ | | | ✓ |
| `~/Videos/Syncthing/Desktop-Windows` | ✓ | ✓ | | | ✓ |
| `~/Documents/ESSENTIALS/SB-LINUX1` | ✓ | ✓ | | | ✓ |
| `~/logseq1` | ✓ | ✓ | | | ✓ |


A few things worth noting from the configs:
  - ~/Vaults/gocryptfs1/Android-sync/Android-NewPipe is covered by both rclone cloudsync and Syncthing
  - The three Android-Backups subfolders (NeoBackup, Signal, SeedVault) get rclone android-backups + Syncthing (but the parent
  Android-Backups/ dir is covered by android-backups as a whole)
  - Only ~/logseq1 is synced via Syncthing — ~/logseq (no suffix) is not in any Syncthing config
