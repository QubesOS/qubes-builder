#!/bin/sh

TIMESTAMP=$(date -u +%Y%m%d%H%M)
echo $TIMESTAMP > iso_build_timestamp

SRCIMG=windows-tools-sources.img
ISOIMG=qubes-windows-tools-$TIMESTAMP.iso
MNT=mnt
ISODIR=win-iso-build/

OUTPUT=`sudo kpartx -a -v $SRCIMG`
# sample output: add map loop0p1 (253:1): 0 2095104 linear /dev/loop0 2048
DEV=/dev/mapper/`echo $OUTPUT | cut -f 3 -d ' '`
sudo mount $DEV $MNT

rm -f $ISODIR/*.msi $ISODIR/*.exe
# If no bundle exists, try to copy only pvdrivers
cp $MNT/*.exe $ISODIR/ || cp $MNT/winpvdrivers/*.msi $ISODIR/
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
