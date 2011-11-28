#!/bin/bash

# Configuration by env:
#  - GIT_BASEURL - base url of git repos
#  - GIT_SUBDIR - whose repo to clone
#  - GIT_SUFFIX - git component dir suffix (default .git)
#  - COMPONENT - component to clone
#  - BRANCH - git branch
#  - NO_CHECK=1 - disable signed tag checking
#  - CLEAN=1 - remove previous sources (use git up vs git clone)

[ -r $SCRIPT_DIR/builder.conf ] && source $SCRIPT_DIR/builder.conf

set -e
[ "$DEBUG" = "1" ] && set -x

# Set defaults
: ${GIT_SUBDIR=mainstream}
: ${BRANCH=master}
[ -z "$COMPONENT" ] && { echo "ERROR: COMPONENT not set!"; exit 1; }

: ${GIT_BASEURL=git://git.qubes-os.org}
: ${GIT_SUFFIX=.git}

GIT_URL=$GIT_BASEURL/$GIT_SUBDIR/$COMPONENT$GIT_SUFFIX

branch_var="BRANCH_${COMPONENT}"

if [ -n "${!branch_var}" ]; then
    BRANCH="${!branch_var}"
fi

if [ -d $COMPONENT -a "$CLEAN" != '1' ]; then
    pushd $COMPONENT
    git pull $GIT_URL $BRANCH || exit 1
    git fetch $GIT_URL --tags || exit 1
    popd
else
    rm -rf $COMPONENT
    git clone -b $BRANCH $GIT_URL $COMPONENT
fi

cd $COMPONENT
pwd
LAST_COMMIT=`git log -1 --pretty=oneline|cut -d ' ' -f 1`
TAG=`git tag --contains=$LAST_COMMIT`

if [ -z "$TAG" -a "$NO_CHECK" != "1" ]; then
    echo "Source is not tagged, cannot verify it!"
    exit 1
fi

if [ -n "$TAG" ]; then
    git tag -v $TAG || exit 1
fi

# For xen additionally download sources
if [ "$COMPONENT" = "xen" -o "$COMPONENT" = "kde-dom0" ]; then
    make get-sources
    make verify-sources
fi

if [ "$COMPONENT" = "kernel" ]; then
    make BUILD_FLAVOR=pvops get-sources
    make BUILD_FLAVOR=pvops verify-sources
    make BUILD_FLAVOR=xenlinux get-sources
    make BUILD_FLAVOR=xenlinux verify-sources
fi

cd ..
