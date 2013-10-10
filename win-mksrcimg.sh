#!/bin/sh

IMG=$PWD/windows-sources.img
IMG_MAXSZ=4g
MNT=mnt
SRC=qubes-src

NEW_IMAGE=no
WINDOWS_BUILDER_CONTENT="Makefile Makefile.generic Makefile.windows builder.conf.default
                        get-sources.sh verify-git-tag.sh
                        scripts-windows windows-build-files"

if [ -z "$COMPONENTS" ]; then
    echo "Empty COMPONENTS setting, nothing to copy"
    exit 1
fi

if [ ! -r "$BUILDERCONF" ]; then
    echo "No $BUILDERCONF file, you need to prepare one (check builder.conf.default)"
    exit 1
fi

if [ ! -r "$IMG" ]; then
    echo "Creating image file with Windows sources..."
    truncate -s $IMG_MAXSZ $IMG
    parted -s $IMG mklabel msdos
    parted -s $IMG mkpart primary ntfs 1 $IMG_MAXSZ
    NEW_IMAGE=yes
fi

OUTPUT=`sudo kpartx -a -v $IMG`
# sample output: add map loop0p1 (253:1): 0 2095104 linear /dev/loop0 2048
DEV=/dev/mapper/`echo $OUTPUT | cut -f 3 -d ' '`

if [ "$NEW_IMAGE" = "yes" ]; then
    sudo mkfs.ntfs -q --fast $DEV || exit 1
fi
mkdir -p $MNT || exit 1
sudo mount $DEV $MNT -o uid=`id -u` || exit 1
rsync -r $WINDOWS_BUILDER_CONTENT $MNT/ || exit 1
cp $BUILDERCONF $MNT/builder.conf || exit 1
# clean qubes-src
rm -rf $MNT/qubes-src
mkdir -p $MNT/qubes-src

for C in $COMPONENTS; do
    rsync -r $SRC/$C $MNT/qubes-src/ || exit 1
done

sudo umount  $MNT
sudo kpartx -d $IMG
echo "Image file at: $IMG"
echo "Connect it to some Windows (on Qubes use qvm-block) and enjoy using qubes-builder there"
echo "When you finish, unmount it from Windows and execute \"make windows-image-extract\" here"
