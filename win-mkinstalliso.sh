#!/bin/sh

SRCIMG=winpvsources.img
ISOIMG=pvdrivers-win7.iso
MNT=mnt
ISODIR=win-iso/

OUTPUT=`sudo kpartx -a -v $SRCIMG`
# sample output: add map loop0p1 (253:1): 0 2095104 linear /dev/loop0 2048
DEV=/dev/mapper/`echo $OUTPUT | cut -f 3 -d ' '`
sudo mount $DEV $MNT

rm -f $ISODIR/*.msi
cp $MNT/winpvdrivers/gplpv_*.msi $MNT/core/win/qubes*.msi $MNT/*.exe $ISODIR/
if [ $? -ne 0 ]; then
    echo "No installation files found! Have you built the drivers?"
    sudo umount  $MNT 
    sudo kpartx -d $SRCIMG
    exit 1
fi

sudo umount  $MNT
sudo kpartx -d $SRCIMG
genisoimage -o $ISOIMG -m .gitignore -JR $ISODIR

# Now, make also an RPM containg this ISO
rpmbuild --target noarch --define "_rpmdir rpm/" -bb win-iso.spec
