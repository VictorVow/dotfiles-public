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

#### Exclusions
Exclusions are stored in the `exclusionmodel` and `backupprofilemodel` tables of `~/.var/app/com.borgbase.Vorta/data/Vorta/settings.db`.

**Preset exclusions** (Vorta built-in categories, checked in UI):

| Preset | BorgBase.com | rsync.net | SSD-1TB-Transcend |
|--------|:---:|:---:|:---:|
| chromium-cache | ✓ | ✓ | ✓ |
| google-chrome-cache | ✓ | ✓ | ✓ |
| brave-cache | ✓ | ✓ | ✓ |
| firefox-cache | ✓ | ✓ | ✓ |
| node-cache | ✓ | ✓ | ✓ |
| python-cache | ✓ | ✓ | ✓ |
| rust-artefacts | ✓ | ✓ | ✓ |
| docker-artefacts | ✓ | ✓ | |
| cache-files | ✓ | ✓ | |
| recycle-bin-trash | ✓ | ✓ | |

**Raw exclusions — BorgBase.com & rsync.net** (identical lists):

Note: `SSD-1TB-Transcend` is ignored. And so is Vorta's preset exclusions.

```
node_modules
/home/*/node_modules
/home/boss/.babylonia-terminal/
/home/boss/.bitmonero/lmdb/data.mdb
/home/boss/.cache/
/home/boss/.config/GeForce NOW/Cache/
/home/boss/.config/GeForce NOW/Service Worker/
/home/boss/.config/GeForce NOW/Code Cache/
/home/boss/.config/google-chrome/Default/Service Worker/
/home/boss/.config/itch/Partitions/itchio-4159193/Cache/
/home/boss/.config/itch/Partitions/itchio-4159193/Code Cache/
/home/boss/.config/itch/Partitions/itchio-4159193/Service Worker/
/home/boss/.config/lbry/Cache/
/home/boss/.config/Logseq/search/
/home/boss/.config/Signal/
/home/boss/.config/syncthing/index-v0.14.0.db/
/home/boss/.config/WorkFlowy/Cache/
/home/boss/.gradle/caches/
/home/boss/.gradle/wrapper/
/home/boss/.local/share/baloo/
/home/boss/.local/share/containers/storage/overlay/
/home/boss/.local/share/flatpak/
/home/boss/.local/share/lbry/lbrynet/blobfiles/
/home/boss/.local/share/lutris/
/home/boss/.local/share/plasma-vault/
/home/boss/.local/share/pnpm/
/home/boss/.local/share/Steam/
/home/boss/.local/share/stremio/
/home/boss/.local/share/Tabletop Simulator/
/home/boss/.local/share/TelegramDesktop/tdata/
/home/boss/.local/share/Trash/
/home/boss/.local/share/Vircadia/Interface/ktx_cache/
/home/boss/.local/share/waydroid/data/
/home/boss/.npm/_cacache/
/home/boss/.nuget/packages/
/home/boss/.recoll/
/home/boss/.rustup/toolchains/
/home/boss/.var/app/com.brave.Browser/cache/BraveSoftware/Brave-Browser/Default/Cache/
/home/boss/.var/app/com.brave.Browser/cache/BraveSoftware/Brave-Browser/Default/Code Cache/
/home/boss/.var/app/com.discordapp.Discord/config/discord/Code Cache/
/home/boss/.var/app/com.discordapp.Discord/config/discord/Cache/
/home/boss/.var/app/com.gitlab.KRypt0n_.an-anime-game-launcher/data/anime-game-launcher/
/home/boss/.var/app/com.logseq.Logseq/config/Logseq/search/
/home/boss/.var/app/com.logseq.Logseq/config/Logseq/Cache/
/home/boss/.var/app/com.slack.Slack/config/Slack/Cache/Cache_Data/
/home/boss/.var/app/com.slack.Slack/config/Slack/Service Worker/CacheStorage/
/home/boss/.var/app/com.spotify.Client/cache/spotify/Browser/Cache/Cache_Data/
/home/boss/.var/app/com.stremio.Stremio/.stremio-server/stremio-cache/
/home/boss/.var/app/com.usebottles.bottles/data/bottles/
/home/boss/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/
/home/boss/.var/app/com.visualstudio.code/cache/Cypress/
/home/boss/.var/app/io.freetubeapp.FreeTube/config/FreeTube/Cache/
/home/boss/.var/app/io.gitlab.librewolf-community/cache/
/home/boss/.var/app/net.lutris.Lutris/cache/lutris/
/home/boss/.var/app/net.lutris.Lutris/data/lutris/runners/wine/
/home/boss/.var/app/org.chromium.Chromium/cache/
/home/boss/.var/app/org.chromium.Chromium/config/chromium/Default/Service Worker/
/home/boss/.var/app/org.kde.dolphin/cache/
/home/boss/.var/app/org.kde.dolphin/data/Trash/
/home/boss/.var/app/org.mozilla.firefox/cache/mozilla/firefox/09muof4b.MASTER/cache2/entries/
/home/boss/.var/app/org.mozilla.firefox/cache/mozilla/firefox/w4q5aadv.LEISURE/cache2/entries/
/home/boss/.var/app/org.mozilla.firefox/cache/mozilla/firefox/89q24drb.CIKFORUM/cache2/entries/
/home/boss/.var/app/org.mozilla.firefox/cache/mozilla/firefox/6nxpopo7.PLAIN/cache2/entries/
/home/boss/.var/app/org.mozilla.firefox/cache/mozilla/firefox/kxnl5iqx.WORK/cache2/entries/
/home/boss/.var/app/org.mozilla.firefox/cache/tmp/
/home/boss/.var/app/org.polymc.PolyMC/data/polymc/
/home/boss/.var/app/org.telegram.desktop/data/TelegramDesktop/tdata/user_data/
/home/boss/.var/app/org.telegram.desktop/data/TelegramDesktop/tdata/user_data#2/
/home/boss/.var/app/io.lbry.lbry-app/data/lbry/lbrynet/blobfiles/
/home/boss/.wine/drive_c/
/home/boss/Documents/Dev/Android/Sdk/
/home/boss/Documents/Git/
/home/boss/Documents/Linux.iso
/home/boss/Documents/MUSEUM/Docker/NocoDB/
/home/boss/Documents/MUSEUM/Docker/LanguageTool/optional_ngrams/en/
/home/boss/Documents/MUSEUM/Docker/zlib-searcher/index/
/home/boss/Documents/OPTIONAL/ISOs/
/home/boss/Documents/OPTIONAL/Android/PocophoneF1-beryllium/ROMs/
/home/boss/Documents/OPTIONAL/Android/PocophoneF1-beryllium/Partitions/
/home/boss/Documents/VMs/
/home/boss/Downloads/MEGA/
/home/boss/Games/1Git/
/home/boss/Games/Adult/
/home/boss/Games/byond-513/
/home/boss/Games/byond-ss13/
/home/boss/Games/epic-games/
/home/boss/Games/gog-galaxy/drive_c/windows/
/home/boss/Games/gog-games/
/home/boss/Games/itchio-games/
/home/boss/Games/magic-the-gathering-online/
/home/boss/Games/minecraft/
/home/boss/Games/minecraft-all/
/home/boss/Games/multimc/
/home/boss/Games/Pirated/
/home/boss/Games/SteamLibrary/steamapps/
/home/boss/Games/SteamOther/
/home/boss/Games/XMage/
/home/boss/logseq/graphs/logseq-apex/backups/
/home/boss/Mounts/
/home/boss/Vaults/gocryptfs1/1Vault/Android-SwiftBackup
/home/boss/Vaults/gocryptfs1/1Vault/Android-WhatsApp-OLD-FULL
/home/boss/Vaults/gocryptfs1/1Vault/wikispooks/
/home/boss/Vaults/gocryptfs1/Android-sync/Android-Backups/
/home/boss/Vaults/gocryptfs1/Android-sync/Android-CORE/1VideoMedia
/home/boss/Vaults/gocryptfs1/Android-sync/Android-NewPipe/
/home/boss/Vaults/gocryptfs1/Android-sync/Android-WhatsApp/Databases/
/home/boss/Vaults/gocryptfs1/Browsers/MASTER/firefox/
/home/boss/Vaults/gocryptfs1/Browsers/MASTER/profile/cache2/entries/
/home/boss/Vaults/gocryptfs1/Browsers/MASTER/profile/storage/default/
/home/boss/Vaults/gocryptfs1/Calibre/Calibre-Library/full-text-search.db
/home/boss/Vaults/gocryptfs1/Cloud/Cloud Drive/Android-MP/.stversions/1-Export to PC/Android-NewPipe/
/home/boss/Vaults/gocryptfs1/Cloud/Cloud Drive/Android-MP/1-Export to PC/Android-NewPipe/NewPipe-Video/
/home/boss/Vaults/gocryptfs1/Thunderbird/profile/cache2/entries/
/home/boss/Vaults/gocryptfs1/Thunderbird/profile/calendar-data/
/home/boss/Vaults/gocryptfs1/Thunderbird/thunderbird/
/home/boss/Vaults/gocryptfs2/
/home/boss/Videos/1-Downloading/
/home/boss/Videos/2-Complete/
/home/boss/Videos/9-LBRY/
/home/boss/Videos/NewPipe-Video/
/home/boss/Videos/Replays/
/home/boss/Videos/Syncthing/
/home/boss/Videos/X/
/home/boss/vmware/
```

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
