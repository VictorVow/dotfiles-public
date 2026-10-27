#!/usr/bin/env bash
# Path B steps B1–B4 (see README.md): partition the new disk, create its own VG with a
# swap LV + btrfs root LV (subvolumes @, @home), then the first live rsync pass.
# No downtime. Run on the server, inside tmux:  NEW_MODEL="990 PRO" bash btrfs-1-prepare.sh
# Afterwards run btrfs-2-downtime.sh when ready for the outage.
set -euxo pipefail

OLD=${OLD:-/dev/nvme0n1}      # current boot disk — verify with lsblk
NEW=${NEW:-/dev/nvme1n1}      # target disk, WILL BE WIPED — verify with lsblk
NEW_MODEL=${NEW_MODEL:?set NEW_MODEL to a substring of: lsblk -dno MODEL $NEW}
VG=${VG:-lord-vg}             # must differ from the old VG name (ubuntu-vg)
SWAP_SIZE=${SWAP_SIZE:-12G}
[[ $NEW == *nvme* ]] && P=${NEW}p || P=$NEW   # nvme0n1p3 vs sda3

# guards: right disk, nothing on it mounted, VG name free
lsblk -dno MODEL "$NEW" | grep -q "$NEW_MODEL"
! findmnt -rn -o SOURCE | grep -q "^$P"
! sudo vgs "$VG" >/dev/null 2>&1
lsblk "$NEW"
read -rp "Wipe $NEW ($(lsblk -dno MODEL "$NEW")) and build $VG on it? Type yes: " ok; [[ $ok == yes ]]

# B1: copy old GPT, randomize GUIDs (duplicates confuse mount/boot), p3 fills the disk
sudo sgdisk "$OLD" -R "$NEW"
sudo sgdisk -G "$NEW"
sudo sgdisk -d3 -n3:0:0 -t3:8E00 "$NEW"
sudo partprobe "$NEW"; sudo udevadm settle

# B2: separate VG so the disks stay independent (pulling the old one leaves no missing PV)
sudo pvcreate -y "${P}3"
sudo vgcreate "$VG" "${P}3"
sudo lvcreate -y -Wy -L "$SWAP_SIZE" -n swap "$VG"
sudo lvcreate -y -Wy -l 100%FREE -n root-btrfs "$VG"
sudo mkfs.btrfs -f -L root "/dev/$VG/root-btrfs"
sudo mkswap -L swap "/dev/$VG/swap"

# B3
sudo mount "/dev/$VG/root-btrfs" /mnt
sudo btrfs subvolume create /mnt/@
sudo btrfs subvolume create /mnt/@home

# B4: first pass while live. /home is on the same fs as /, so exclude it from the / pass
sudo rsync -aAXHSx --info=progress2 --exclude=/swap.img --exclude=/swapfile --exclude='/home/*' / /mnt/@/
sudo rsync -aAXHSx --info=progress2 /home/ /mnt/@home/
echo PREPARE_DONE
