#!/bin/sh

IMG=windows-tools-sources.img
IMG_MAXSZ=1g
MNT=mnt
SRC=../qubes-src

echo "Creating image file with Windows tools sources..."
truncate -s $IMG_MAXSZ $IMG
parted -s $IMG mklabel msdos
parted -s $IMG mkpart primary ntfs 1 $IMG_MAXSZ

OUTPUT=`sudo kpartx -a -v $IMG`
# sample output: add map loop0p1 (253:1): 0 2095104 linear /dev/loop0 2048
DEV=/dev/mapper/`echo $OUTPUT | cut -f 3 -d ' '`

sudo mkfs.ntfs -q --fast $DEV || exit 1
mkdir -p $MNT
sudo mount $DEV $MNT
sudo mkdir $MNT/winpvdrivers
sudo rsync --exclude-from win-sources.exclude -r $SRC/vmm-xen-windows-pvdrivers/* $MNT/winpvdrivers/
if [ -d $SRC/core-agent-windows ]; then
    sudo mkdir $MNT/core
    sudo rsync --exclude-from win-sources.exclude -r $SRC/core-agent-windows/* $MNT/core/
    sudo rsync --exclude-from win-sources.exclude -r $SRC/core-vchan-xen/vchan $MNT/core/
fi
if [ -d $SRC/gui-agent-windows ]; then
    sudo mkdir $MNT/gui-agent
    sudo rsync --exclude-from win-sources.exclude -r $SRC/gui-agent-windows/* $MNT/gui-agent/
    sudo rsync --exclude-from win-sources.exclude -r $SRC/gui-common $MNT/gui-agent/
fi

sudo rsync win-srcimg-files/* $MNT/
sudo umount  $MNT
sudo kpartx -d $IMG
echo "Image file at: $IMG"
