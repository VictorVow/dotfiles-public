# lord-ubuntu disk migration (500GB → 4TB NVMe)

Runbook for swapping lord-ubuntu's NVMe with a larger drive with near-zero downtime and no config changes in this repo or the Self-Hosted repos. Works because the root filesystem sits on LVM (`ubuntu-vg` / `ubuntu-lv`).

Two paths — pick one:

- **Path A (steps 1–7): keep ext4.** `pvmove` migrates the data live, zero downtime.
- **Path B (section at the bottom): also convert to btrfs.** New btrfs LV + rsync + reboot. ~10 min downtime, no pvmove needed, old disk stays a complete bootable rollback.

Path B is scripted (done on lord-ubuntu 2026-10-27, old SK hynix 512GB → Samsung 990 PRO 4TB). Copy both scripts to the server and run them inside tmux. Override the device/VG defaults with env vars (`OLD`, `NEW`, `VG`, `SWAP_SIZE`) after checking `lsblk`:

- [btrfs-1-prepare.sh](btrfs-1-prepare.sh) — B1–B4, live, no downtime. It asks for confirmation before wiping `NEW`.
- [btrfs-2-downtime.sh](btrfs-2-downtime.sh) — B5–B7. This **starts the outage** and ends ready for the B8 shutdown and disk swap.

```bash
scp scripts/migration/btrfs-*.sh lord@lord-ubuntu:/tmp/
NEW_MODEL="990 PRO" bash /tmp/btrfs-1-prepare.sh 2>&1 | tee /tmp/btrfs-1.log
NEW_MODEL="990 PRO" bash /tmp/btrfs-2-downtime.sh 2>&1 | tee /tmp/btrfs-2.log
```

After Path B, lord-ubuntu runs on `lord-vg` (`swap` 12G + `root-btrfs` with subvolumes `@` and `@home`). Before a future migration, re-check the layout below and adapt it: the old VG is no longer `ubuntu-vg`, so the new disk's VG needs a different name than `lord-vg`.

## Layout before the 2026-10-27 migration (verified 2026-10-26)

```
nvme0n1                       ~477G  SK hynix PC401
├─nvme0n1p1                   1G     vfat  → /boot/efi  (UUID=89F8-F8FE)
├─nvme0n1p2                   2G     ext4  → /boot      (UUID=10e3efdf-035a-48fc-acb0-72dda0bd29c6)
└─nvme0n1p3                   473.9G LVM2_member
   └─ubuntu--vg-ubuntu--lv    473.9G ext4  → /          (dm-uuid-LVM-... in fstab)
```

No LUKS. Swap is a file (`/swap.img`, `/swapfile`) inside `/`. `lord` has passwordless sudo. fstab mounts `/` by LVM device-mapper UUID (unchanged by the migration) and `/boot`, `/boot/efi` by filesystem UUID (updated in step 4).

## Why no config changes are needed

Hostname, IP, Tailscale identity, SSH host keys — all unchanged (same machine). Everything in `nix/` lives in `/home/lord` and moves with the LV. Self-Hosted deploys go over SSH/Docker to paths on `/` — nothing references device names. The only UUID-sensitive items are the two fstab lines (step 4) and the EFI boot entry (step 5).

## Prerequisites

- New 4TB NVMe installed in the second M.2 slot (or a USB NVMe enclosure).
- Run everything in tmux on lord-ubuntu (`tmux new -s migrate`) so an SSH drop can't kill `pvmove`.
- Commands run on lord-ubuntu as `lord`. Below, `OLD=/dev/nvme0n1` and `NEW=/dev/nvme1n1` — **verify with `lsblk` first; don't assume the numbering.**

## 1. Partition the new disk

Copy the old GPT, then recreate p3 to fill the whole disk:

```bash
sudo sgdisk /dev/nvme0n1 -R /dev/nvme1n1          # copy partition table
sudo sgdisk -G /dev/nvme1n1                       # randomize disk + partition GUIDs — REQUIRED, duplicates cause mount/boot confusion
sudo sgdisk -d3 -n3:0:0 -t3:8E00 /dev/nvme1n1     # p3: fill remaining space, type LVM
sudo partprobe /dev/nvme1n1
```

## 2. Copy /boot/efi and /boot

Fresh filesystems (new UUIDs — that's fine, step 4 fixes fstab):

```bash
sudo mkfs.vfat -F32 /dev/nvme1n1p1
sudo mkfs.ext4 -L boot /dev/nvme1n1p2
sudo mkdir -p /mnt/newboot /mnt/newefi
sudo mount /dev/nvme1n1p2 /mnt/newboot
sudo mount /dev/nvme1n1p1 /mnt/newefi
sudo rsync -aAXH /boot/ /mnt/newboot/
sudo rsync -aAXH /boot/efi/ /mnt/newefi/
```

## 3. Live-migrate the data (pvmove)

The LV stays mounted and serving the whole time — Docker, Tailscale, Forgejo, everything keeps running.

```bash
sudo pvcreate /dev/nvme1n1p3
sudo vgextend ubuntu-vg /dev/nvme1n1p3
sudo pvmove /dev/nvme0n1p3 /dev/nvme1n1p3   # ~30-60 min for ~400G, resumable if interrupted
sudo vgreduce ubuntu-vg /dev/nvme0n1p3
sudo pvremove /dev/nvme0n1p3
```

## 4. Switch /boot and /boot/efi to the new partitions

```bash
EFI_UUID=$(sudo blkid -s UUID -o value /dev/nvme1n1p1)
BOOT_UUID=$(sudo blkid -s UUID -o value /dev/nvme1n1p2)
sudo sed -i.bak "s|UUID=89F8-F8FE|UUID=$EFI_UUID|; s|UUID=10e3efdf-035a-48fc-acb0-72dda0bd29c6|UUID=$BOOT_UUID|" /etc/fstab
sudo umount /boot/efi /boot
sudo umount /mnt/newboot /mnt/newefi
sudo mount /dev/nvme1n1p2 /boot
sudo mount /dev/nvme1n1p1 /boot/efi
sudo mount -a && findmnt / /boot /boot/efi   # verify clean
```

## 5. Reinstall boot files onto the new ESP

```bash
sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck
sudo update-grub
sudo update-initramfs -u -k all
sudo efibootmgr -v   # confirm a 'ubuntu' entry → HD(1,GPT,<new p1 GUID>,...)
```

## 6. Shut down and pull the old drive

```bash
sudo shutdown -h now
```

Remove the old NVMe, power on. If the BIOS doesn't auto-boot, pick the `ubuntu` entry once — the ESP also has the `/EFI/BOOT` removable fallback. Keep the old disk untouched on a shelf for a couple of weeks as a complete rollback.

After removal the new disk may enumerate as `nvme0n1` — harmless, nothing references device names.

## 7. Claim the extra space (online, no downtime)

```bash
sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv   # -r grows ext4 in place
```

Takes `/` from ~466G to ~3.6T.

## Optional: keep the old 500GB in the machine

If there are two M.2 slots, leave it in and reuse it as a second PV:

```bash
sudo pvcreate /dev/nvme0n1p3 && sudo vgextend ubuntu-vg /dev/nvme0n1p3
```

Then carve out LVs for backups or scratch data.

## Rollback

- Before step 6: the old disk still holds a complete bootable copy of everything (partitions untouched). If something looks wrong, `vgreduce`/`pvremove` the new disk, restore fstab from `/etc/fstab.bak`, remount the old `/boot`+EFI, re-run steps 4-5 against the old partitions.
- After step 6: put the old drive back — it boots the system exactly as it was.

## Gotchas

- Never skip `sgdisk -G` after `-R` — duplicate GPT GUIDs are a real footgun when both disks are present.
- Run `pvmove` inside tmux; it's resumable but a killed foreground process in a dropped SSH session is a nuisance.
- `pvmove` is block-level, so it copies used *and* free extents of the LV — for ~474G expect ~30-60 min at NVMe speeds.

---

# Path B: migrate AND convert to btrfs

> Migration in progress (started 2026-10-27). New disk = Samsung 990 PRO 4TB, attached via USB, enumerates as `/dev/nvme1n1` (not /dev/sdX — enclosure passes NVMe through).
>
> - [x] B1 partition new disk
> - [x] B2 PV + swap LV + root-btrfs LV + mkfs
> - [x] B3 subvolumes @, @home
> - [ ] B4 first rsync pass (live) — running in tmux `migrate` on lord-ubuntu
> - [ ] B5 downtime: stop docker, delta rsync --delete
> - [ ] B6 new fstab
> - [ ] B7 /boot + efi + grub + initramfs (chroot)
> - [ ] B8 reboot onto new disk
> - [ ] B9 verify + afterwards
>
> Rollback at any point before B8: `lvremove` new LVs, `vgreduce`/`pvremove` nvme1n1p3 — zero evidence.

Downtime: one reboot (~5–10 min) plus a short delta-rsync window where writers are stopped. No pvmove — LVM is only used to hold the new LV. The old disk is untouched throughout, so rollback = put it back / boot it in the BIOS menu.

Verified facts this plan depends on (2026-10-26): 65 running docker containers; swap is 10G across `/swap.img` + `/swapfile` (btrfs can't host swapfiles → dedicated swap LV); no DB services running on the host itself (all state lives in docker volumes/bind mounts on `/`).

## B1. Partition the new disk

Same as step 1 above (sgdisk copy + `-G` + resized p3 of type `8E00`).

## B2. New PV + VG + btrfs root LV + swap LV

```bash
sudo pvcreate /dev/nvme1n1p3
sudo vgcreate lord-vg /dev/nvme1n1p3
sudo lvcreate -L 12G -n swap lord-vg
sudo lvcreate -l 100%FREE -n root-btrfs lord-vg
sudo mkfs.btrfs -L root /dev/lord-vg/root-btrfs
sudo mkswap -L swap /dev/lord-vg/swap
```

Separate VG, not `vgextend ubuntu-vg`: the disks stay independent, so pulling the old one doesn't leave a VG with a missing PV, and both can sit in the machine later without LV name clashes.

## B3. Mount btrfs, create subvolumes

```bash
sudo mount /dev/lord-vg/root-btrfs /mnt
sudo btrfs subvolume create /mnt/@
sudo btrfs subvolume create /mnt/@home
```

That's enough. Subvolumes are for snapshot boundaries — `/home` is the obvious split (back up user data on a different cadence than the OS). Docker keeps its own `/var/lib/docker` inside `@` — don't split it into its own subvolume.

## B4. First rsync pass — system stays live

Run in tmux (`tmux new -s migrate`) — the pass takes ~1h.

```bash
sudo rsync -aAXHSx --info=progress2 \
  --exclude='/swap.img' --exclude='/swapfile' --exclude='/home/*' \
  / /mnt/@/
sudo rsync -aAXHSx --info=progress2 /home/ /mnt/@home/
```

`-x` stays on one filesystem (skips `/boot`, `/boot/efi`, `/proc`, `/sys`, ...). Swapfiles excluded — they're replaced by the swap LV. `/home/*` excluded because `/home` is on the same filesystem as `/` — without it the ~237G of `/home` lands in `@` too (hidden under the `@home` mount, wasting space and ~30 min).

## B5. Downtime window — stop writers, delta pass

```bash
sudo systemctl stop docker.socket docker.service containerd   # stops all containers
sudo systemctl stop nfs-server nix-daemon.socket nix-daemon cron   # other writers to /
# cass timers can be left — worst case they re-index

sudo rsync -aAXHSx --delete \
  --exclude='/swap.img' --exclude='/swapfile' --exclude='/home/*' \
  / /mnt/@/          # delta pass — minutes, not an hour
sudo rsync -aAXHSx --delete /home/ /mnt/@home/
```

## B6. Fix the new root's fstab

Edit `/mnt/@/etc/fstab` (NOT `/etc/fstab`):

```
/dev/mapper/lord--vg-root--btrfs    /         btrfs  defaults,subvol=@           0 0
/dev/mapper/lord--vg-root--btrfs    /home     btrfs  defaults,subvol=@home       0 0
/dev/mapper/lord--vg-swap           none      swap   sw                          0 0
UUID=<new-boot-uuid>                /boot     ext4   defaults                    0 1
UUID=<new-efi-uuid>                 /boot/efi vfat   defaults                    0 1
```

Delete the `/swap.img` and `/swapfile` lines. Get the UUIDs with `blkid /dev/nvme1n1p1 /dev/nvme1n1p2` (or reuse the old ones by cloning the filesystem UUIDs — either works; fresh UUIDs are cleaner).

Grub also needs `rootflags=subvol=@` — added automatically by update-grub in B7 (the chroot must be a real `subvol=@` mount).

## B7. /boot, /boot/efi, bootloader

```bash
# copy boot partitions to the new disk (same as step 2)
sudo mkfs.vfat -F32 /dev/nvme1n1p1
sudo mkfs.ext4 -L boot /dev/nvme1n1p2
sudo mkdir -p /mnt/newboot /mnt/newefi
sudo mount /dev/nvme1n1p2 /mnt/newboot && sudo mount /dev/nvme1n1p1 /mnt/newefi
sudo rsync -aAXH --exclude='/efi/*' /boot/ /mnt/newboot/ && sudo rsync -rtH /boot/efi/ /mnt/newefi/   # vfat: no owners/ACLs/xattrs

# chroot into the new root to install grub + initramfs.
# Mount subvol=@ at its own mountpoint — chrooting into the /mnt/@ directory makes update-grub fail with
# "grub-probe: cannot find a device for /". rslave the rbinds so a later umount -R can't take down host /dev,/sys,/run.
R=/tmp/newroot; sudo mkdir -p $R
sudo mount -o subvol=@ /dev/lord-vg/root-btrfs $R && sudo mount --make-private $R
sudo mount --bind /mnt/newboot $R/boot
sudo mount --bind /mnt/newefi $R/boot/efi
for d in dev proc sys run; do sudo mount --rbind /$d $R/$d; sudo mount --make-rslave $R/$d; done
sudo chroot $R

# inside chroot:
dpkg -s btrfs-progs >/dev/null || apt install btrfs-progs   # needed in initramfs to mount / (already installed on lord-ubuntu)
# no /etc/default/grub edit: update-grub detects the subvol=@ root and adds rootflags=subvol=@ itself (adding it manually duplicates it)
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck
update-grub
update-initramfs -u -k all
exit
```

`btrfs-progs` is required inside initramfs or the kernel can't assemble/mount the btrfs root — grub's initramfs hook includes it automatically once installed.

## B8. Reboot onto the new disk

```bash
sudo umount -R /tmp/newroot; sudo umount /mnt/newefi /mnt/newboot /mnt
sudo shutdown -h now
```

If the new disk is in a USB/Thunderbolt enclosure: swap it into the internal M.2 slot now (old disk out, onto the shelf) rather than relying on the BIOS booting from Thunderbolt. Power on; pick the `ubuntu` EFI entry if it doesn't come up first (the stale entry for the old ESP fails over harmlessly). Verify: `findmnt /` should show btrfs `subvol=@`. Then `sudo systemctl start docker` if it didn't auto-start — containers come up from the copied volumes, untouched.

## B9. Afterwards

- Old disk: leave powered off / pulled as rollback (it's a complete frozen snapshot of the system at B5 time).
- Reclaim the old disk later (if it goes back in): `sudo vgremove ubuntu-vg`, then `pvcreate` + `vgextend lord-vg`.
- Snapshots: install `snapper` or just `btrfs subvolume snapshot / /@snap-$(date +%F)` before risky upgrades. `apt-btrfs-snapshot`-style hooks or `timeshift` (rsync mode doesn't apply — use its btrfs mode) are the low-effort options.
- Docker uses the containerd `overlayfs` snapshotter (`docker info -f '{{.Driver}}'`), which works on btrfs unchanged — no driver switch. Container-heavy write patterns fragment more on btrfs; enable `autodefrag` in the mount options if you see slowdowns.
- Swap: `swapon -a` should bring up the LV swap (it's in the new fstab). Verify with `swapon -s`.

## B-rollback

- Before B8: nothing has booted off the new disk; `umount /mnt`, `vgremove lord-vg`, `pvremove /dev/nvme1n1p3`, restart the services stopped in B5 — done, zero evidence.
- After B8: the old disk is a full bootable copy. Pull the new disk (or pick the old `ubuntu` entry in BIOS), boot, restart docker. Delta rsync back any data written since B5 if needed (rare — only if you ran for days on the new disk).
