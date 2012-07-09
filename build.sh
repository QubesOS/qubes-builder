#!/bin/sh

if [ $# -lt 2 ]; then
    echo "Usage: $0 DIST COMPONENT [username]"
    exit 1
fi

[ -r ./builder.conf ] && source ./builder.conf

set -e
shopt -s nullglob
[ "$DEBUG" = "1" ] && set -x

DIST=$1
COMPONENT=$2
RUN_AS_USER="user"
if [ $# -gt 2 ]; then
    RUN_AS_USER=$3
fi

SCRIPT_DIR=$PWD

: ${MAKE_TARGET=rpms}


ORIG_SRC=$PWD/qubes-src/$COMPONENT
DIST_SRC_ROOT=$PWD/$DIST/home/user/qubes-src/
DIST_SRC=$DIST_SRC_ROOT/$COMPONENT

REQ_PACKAGES="build-pkgs-$COMPONENT.list"

export USER_UID=$UID
if ! [ -e $DIST/home/user/.prepared_base ]; then
    sudo -E ./prepare-chroot $PWD/$DIST $DIST
    touch $DIST/home/user/.prepared_base
fi

if [ -r $REQ_PACKAGES ] && [ $REQ_PACKAGES -nt $DIST/home/user/.installed_$REQ_PACKAGES ]; then
    sed "s/DIST/$DIST/g" $REQ_PACKAGES > build-pkgs-temp.list
    sudo -E ./prepare-chroot $PWD/$DIST $DIST build-pkgs-temp.list
    rm -f build-pkgs-temp.list
    touch $DIST/home/user/.installed_$REQ_PACKAGES
fi

if ! [ -r $PWD/$DIST/proc/cpuinfo ]; then
    sudo mount -t proc proc $PWD/$DIST/proc
fi


mkdir -p $DIST_SRC_ROOT
sudo rm -rf $DIST_SRC
cp -alt $DIST_SRC_ROOT $ORIG_SRC
rm -rf $DIST_SRC/rpm/{x86_64,i686,noarch,SOURCES}
# Disable rpm signing in chroot - there are no signing keys
sed -i -e 's/rpm --addsign/echo \0/' $DIST_SRC/Makefile*
[ -x $ORIG_SRC/qubes-builder-pre-hook.sh ] && source $ORIG_SRC/qubes-builder-pre-hook.sh
sudo -E chroot $DIST su - -c "cd /home/user/qubes-src/$COMPONENT; NO_SIGN="$NO_SIGN" make $MAKE_TARGET" $RUN_AS_USER
[ -x $ORIG_SRC/qubes-builder-post-hook.sh ] && source $ORIG_SRC/qubes-builder-post-hook.sh
for i in $DIST_SRC/rpm/*; do
    ARCH_RPM_DIR=$ORIG_SRC/rpm/`basename $i`
    mkdir -p $ARCH_RPM_DIR
    mv -vt $ARCH_RPM_DIR $i/*
done
if [ $COMPONENT == "installer" ]; then
    if [ $MAKE_TARGET == "iso" ]; then
        if [ -d $DIST_SRC/build/work ]; then
            sudo rm -fr $ORIG_SRC/build/ISO
            sudo rm -fr $ORIG_SRC/build/work
            sudo mv $DIST_SRC/build/work $ORIG_SRC/build/
            sudo mv $DIST_SRC/build/ISO $ORIG_SRC/build/
        fi
    fi
fi
if [ $COMPONENT == "dom0-updates" ]; then
    # include additional dirs
    for dir in nvidia-prioprietary-drivers; do
	for i in $DIST_SRC/$dir/rpm/*; do
	    ARCH_RPM_DIR=$ORIG_SRC/$dir/rpm/`basename $i`
	    mkdir -p $ARCH_RPM_DIR
	    mv -vt $ARCH_RPM_DIR $i/*
	done
    done
fi
