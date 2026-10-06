#!/bin/bash
# Sets up a blank NVMe as an ext4 data drive mounted at /mnt/data.
# Edit DISK for a different drive (use the /dev/disk/by-id name, never nvme0n1).
set -euo pipefail

DISK=/dev/disk/by-id/nvme-SAMSUNG_MZVL22T0HBLB-00BL7_S64SNF0R313160
PART=$DISK-part1
MNT=/mnt/data
OWNER=ryan

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
[ -b "$DISK" ] || { echo "Disk $DISK not found."; exit 1; }

# Refuse to touch the disk unless it is still blank and unmounted.
if [ "$(lsblk -nro NAME "$DISK" | wc -l)" -ne 1 ] || [ -n "$(lsblk -nro FSTYPE "$DISK")" ]; then
    echo "Disk is not blank (has partitions or a filesystem). Aborting."
    lsblk "$DISK"
    exit 1
fi
if [ "$(findmnt -no SOURCE /)" -ef "$DISK" ] || grep -q "$MNT" /etc/fstab; then
    echo "Unexpected state (root on this disk, or $MNT already in fstab). Aborting."
    exit 1
fi

echo 'type=linux' | sfdisk --label gpt "$DISK"
udevadm settle
[ -b "$PART" ] || { echo "Partition $PART did not appear."; exit 1; }

mkfs.ext4 -L data -m 0 "$PART"
udevadm settle
UUID=$(blkid -s UUID -o value "$PART")

mkdir -p "$MNT"
cp /etc/fstab /etc/fstab.bak
printf 'UUID=%s %s ext4 defaults,noatime,nofail 0 2\n' "$UUID" "$MNT" >> /etc/fstab
systemctl daemon-reload
mount "$MNT"
chown "$OWNER:$OWNER" "$MNT"

echo
echo "Done:"
df -h "$MNT"
