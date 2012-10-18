#!/bin/sh

IMG=winpvsources.img
IMG_MAXSZ=1g
MNT=mnt

truncate -s $IMG_MAXSZ $IMG
parted -s $IMG mklabel msdos
parted -s $IMG mkpart primary ntfs 1 $IMG_MAXSZ

OUTPUT=`sudo kpartx -a -v $IMG`
# sample output: add map loop0p1 (253:1): 0 2095104 linear /dev/loop0 2048
DEV=/dev/mapper/`echo $OUTPUT | cut -f 3 -d ' '`

mkfs.ntfs --fast $DEV || exit 1
mkdir -p $MNT
sudo mount $DEV $MNT
sudo mkdir $MNT/winpvdrivers
sudo rsync --exclude-from win-sources.exclude -r qubes-src/win-pvdrivers/* $MNT/winpvdrivers/
if [ -d qubes-src/core-windows ]; then
    sudo mkdir $MNT/core
    sudo rsync --exclude-from win-sources.exclude -r qubes-src/core-windows/* $MNT/core/
    sudo rsync --exclude-from win-sources.exclude -r qubes-src/core/vchan $MNT/core/
fi
sudo rsync windows-build/* $MNT/
sudo umount  $MNT
sudo kpartx -d $IMG

