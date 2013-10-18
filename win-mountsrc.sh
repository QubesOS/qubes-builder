#!/bin/sh

SRCIMG=windows-sources.img
MNT=mnt

if [ "$1" == "umount" ]; then
sudo umount  $MNT
sudo kpartx -d $SRCIMG
else
OUTPUT=`sudo kpartx -a -v $SRCIMG`
# sample output: add map loop0p1 (253:1): 0 2095104 linear /dev/loop0 2048
DEV=/dev/mapper/`echo $OUTPUT | cut -f 3 -d ' '`
sudo mount $DEV $MNT -o uid=`id -u`,fmask=133
fi
