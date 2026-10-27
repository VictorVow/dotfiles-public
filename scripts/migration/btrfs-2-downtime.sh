#!/usr/bin/env bash
# Path B steps B5–B7 (see README.md) — STARTS THE OUTAGE: stops docker/containerd/nfs/nix-daemon/cron,
# delta rsync, fresh /boot + ESP on the new disk, new fstab, grub + initramfs in a chroot.
# Ends with informational checks and everything unmounted; then `sudo shutdown -h now`, move the
# new disk into the internal slot (B8). Don't restart the services in between — writes would land
# on the old disk only. Run inside tmux:  NEW_MODEL="990 PRO" bash btrfs-2-downtime.sh
set -euxo pipefail

NEW=${NEW:-/dev/nvme1n1}
NEW_MODEL=${NEW_MODEL:?set NEW_MODEL to a substring of: lsblk -dno MODEL $NEW}
VG=${VG:-lord-vg}
[[ $NEW == *nvme* ]] && P=${NEW}p || P=$NEW
R=/tmp/newroot

# guards: btrfs top level from btrfs-1-prepare.sh is on /mnt, p1/p2 about to be formatted are on the new disk
findmnt -n -o SOURCE /mnt | grep -q root--btrfs
lsblk -dno MODEL "$NEW" | grep -q "$NEW_MODEL"

# B5: stop writers, delta pass (silent — no progress output; minutes to tens of minutes)
sudo systemctl stop docker.socket docker.service containerd
sudo systemctl stop nfs-server nix-daemon.socket nix-daemon cron
sudo rsync -aAXHSx --delete --exclude=/swap.img --exclude=/swapfile --exclude='/home/*' / /mnt/@/
sudo rsync -aAXHSx --delete /home/ /mnt/@home/

# B7a: fresh /boot (ext4) + ESP (vfat: no owners/ACLs/xattrs, so -rt)
sudo mkfs.vfat -F32 "${P}1"
sudo mkfs.ext4 -F -L boot "${P}2"
sudo mkdir -p /mnt/newboot /mnt/newefi
sudo mount "${P}2" /mnt/newboot
sudo mount "${P}1" /mnt/newefi
sudo rsync -aAXH --exclude='/efi/*' /boot/ /mnt/newboot/
sudo rsync -rtH /boot/efi/ /mnt/newefi/

# B6: new fstab (old one kept alongside)
EFI_UUID=$(sudo blkid -s UUID -o value "${P}1")
BOOT_UUID=$(sudo blkid -s UUID -o value "${P}2")
sudo cp /mnt/@/etc/fstab /mnt/@/etc/fstab.pre-btrfs
sudo tee /mnt/@/etc/fstab >/dev/null <<FSTAB
# btrfs-on-LVM root, migrated on $(date +%F) - previous fstab in fstab.pre-btrfs
/dev/$VG/root-btrfs  /          btrfs  defaults,subvol=@      0 0
/dev/$VG/root-btrfs  /home      btrfs  defaults,subvol=@home  0 0
/dev/$VG/swap        none       swap   sw                     0 0
UUID=$BOOT_UUID  /boot      ext4   defaults  0 1
UUID=$EFI_UUID   /boot/efi  vfat   defaults  0 1
FSTAB

# B7b: chroot into a real subvol=@ mount — chrooting into the /mnt/@ directory makes update-grub
# fail ("grub-probe: cannot find a device for /"). rslave so umount -R can't unmount host /dev,/sys,/run.
# No /etc/default/grub edit: update-grub adds rootflags=subvol=@ itself.
sudo mkdir -p $R
sudo mount -o subvol=@ "/dev/$VG/root-btrfs" $R
sudo mount --make-private $R
sudo mount --bind /mnt/newboot $R/boot
sudo mount --bind /mnt/newefi $R/boot/efi
for d in dev proc sys run; do sudo mount --rbind /$d $R/$d; sudo mount --make-rslave $R/$d; done
sudo chroot $R /bin/bash -euxc "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck; update-grub; update-initramfs -u -k all"

set +e  # checks are informational
sudo cat $R/etc/fstab
sudo grep -m3 -P '^\s+linux\s' /mnt/newboot/grub/grub.cfg        # expect root=/dev/mapper/...root--btrfs rootflags=subvol=@
sudo cat /mnt/newefi/EFI/ubuntu/grub.cfg                           # search.fs_uuid must be $BOOT_UUID
echo "BOOT_UUID=$BOOT_UUID"
sudo lsinitramfs /mnt/newboot/initrd.img-"$(uname -r)" | grep -E 'btrfs.ko|bin/btrfs$|sbin/lvm$'
sudo efibootmgr | head -6                                          # ubuntu entry → new disk's p1

sudo umount -R $R && sudo umount /mnt/newefi /mnt/newboot /mnt
echo "DOWNTIME_DONE — next: sudo shutdown -h now, swap the disk in (B8)"
