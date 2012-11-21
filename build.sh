#!/bin/bash

if [ $# -lt 2 ]; then
    echo "Usage: $0 DIST COMPONENT [username]"
    exit 1
fi

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
BUILDER_REPO_DIR=$PWD/all-qubes-pkgs/$DIST

MAKE_TARGET_ONLY="${MAKE_TARGET/ */}"
REQ_PACKAGES="build-pkgs-$COMPONENT.list"
[ -r "build-pkgs-$COMPONENT-$MAKE_TARGET_ONLY.list" ] && REQ_PACKAGES="build-pkgs-$COMPONENT-$MAKE_TARGET_ONLY.list"
[ -r "$ORIG_SRC/build-deps.list" ] && REQ_PACKAGES="$ORIG_SRC/build-deps.list"
[ -r "$ORIG_SRC/build-deps-$MAKE_TARGET_ONLY.list" ] && REQ_PACKAGES="$ORIG_SRC/build-deps-$MAKE_TARGET_ONLY.list"

export USER_UID=$UID
if ! [ -e $DIST/home/user/.prepared_base ]; then
    echo "-> Preparing $DIST build environment"
    sudo -E ./prepare-chroot $PWD/$DIST $DIST
    touch $DIST/home/user/.prepared_base
fi

if [ -r $REQ_PACKAGES ] && [ $REQ_PACKAGES -nt $DIST/home/user/.installed_${COMPONENT}_`basename $REQ_PACKAGES` ]; then
    sed "s/DIST/$DIST/g" $REQ_PACKAGES > build-pkgs-temp.list
    echo "-> Installing $COMPONENT build dependencies in $DIST environment"
    sudo -E ./prepare-chroot $PWD/$DIST $DIST build-pkgs-temp.list
    rm -f build-pkgs-temp.list
    touch $DIST/home/user/.installed_${COMPONENT}_`basename $REQ_PACKAGES`
fi

if ! [ -r $PWD/$DIST/proc/cpuinfo ]; then
    sudo mount -t proc proc $PWD/$DIST/proc
fi


mkdir -p $DIST_SRC_ROOT
sudo rm -rf $DIST_SRC
cp -alt $DIST_SRC_ROOT $ORIG_SRC
rm -rf $DIST_SRC/rpm/{x86_64,i686,noarch,SOURCES}
[ -x $ORIG_SRC/qubes-builder-pre-hook.sh ] && source $ORIG_SRC/qubes-builder-pre-hook.sh
# Disable rpm signing in chroot - there are no signing keys
sed -i -e 's/rpm --addsign/@true \0/' $DIST_SRC/Makefile*

BUILD_INITIAL_INFO="-> Building $COMPONENT $MAKE_TARGET_ONLY for $DIST"
BUILD_LOG=
if [ $VERBOSE -eq 0 ]; then
    BUILD_LOG="build-logs/$COMPONENT-$MAKE_TARGET_ONLY-$DIST.log"
    if [ -e "$BUILD_LOG" ]; then
	mv -f "$BUILD_LOG" "$BUILD_LOG.old"
    fi
    BUILD_INITIAL_INFO="$BUILD_INITIAL_INFO (logfile: $BUILD_LOG)..."
fi
echo "$BUILD_INITIAL_INFO"
if [ $VERBOSE -eq 1 ]; then
    sed -i -e 's/rpmbuild/rpmbuild --quiet/' $DIST_SRC/Makefile*
    MAKE_OPTS="$MAKE_OPTS -s"
fi
[ -x $ORIG_SRC/qubes-builder-pre-hook.sh ] && source $ORIG_SRC/qubes-builder-pre-hook.sh
set +e
MAKE_CMD="cd /home/user/qubes-src/$COMPONENT; NO_SIGN='$NO_SIGN' make $MAKE_OPTS $MAKE_TARGET"
if [ $VERBOSE -eq 0 ]; then
    sudo -E chroot $DIST su - -c "$MAKE_CMD" $RUN_AS_USER >$BUILD_LOG 2>&1
    BUILD_RETCODE=$?
else
    sudo -E chroot $DIST su - -c "$MAKE_CMD" $RUN_AS_USER
    BUILD_RETCODE=$?
fi
if [ $BUILD_RETCODE -gt 0 ]; then
    echo "--> build failed!"
    if [ -n "$BUILD_LOG" ]; then
        tail $BUILD_LOG
    fi
    exit 1
fi
set -e
[ -x $ORIG_SRC/qubes-builder-post-hook.sh ] && source $ORIG_SRC/qubes-builder-post-hook.sh
echo "--> Done:"
for i in $DIST_SRC/rpm/*; do
    ARCH_RPM_DIR=$ORIG_SRC/rpm/`basename $i`
    mkdir -p $ARCH_RPM_DIR
    for pkg in $i/*; do
        echo "     qubes-src/$COMPONENT/rpm/`basename $i`/`basename $pkg`"
    done
    mkdir -p $BUILDER_REPO_DIR/rpm
    cp -t $BUILDER_REPO_DIR/rpm $i/*
    mv -t $ARCH_RPM_DIR $i/*
done
if [ $COMPONENT == "installer" ]; then
    if [ "$MAKE_TARGET_ONLY" == "iso" ]; then
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
	    mv -t $ARCH_RPM_DIR $i/*
	done
    done
fi
