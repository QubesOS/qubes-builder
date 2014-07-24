#!/bin/sh

set -e

[ -z "$1" ] && { echo "Usage: $0 <dist>"; exit 1; }

REPO_DIR=$PWD/qubes-rpms-mirror-repo/$1

if [ -d $REPO_DIR/dists ]; then
    pushd $REPO_DIR
    mkdir -p dists/$1/main/binary-amd64
    dpkg-scanpackages . |gzip > dists/$1/main/binary-amd64/Packages.gz
    popd
else
    mkdir -p $REPO_DIR/rpm
    createrepo --update -q $REPO_DIR
fi

if [ `id -u` -eq 0 ]; then
    chown -R --reference=$REPO_DIR $REPO_DIR
fi
