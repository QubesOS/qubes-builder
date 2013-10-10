#!/bin/sh

set -e

[ -z "$1" ] && { echo "Usage: $0 <dist>"; exit 1; }

REPO_DIR=$PWD/qubes-rpms-mirror-repo/$1

mkdir -p $REPO_DIR/rpm
createrepo --update -q $REPO_DIR

if [ `id -u` -eq 0 ]; then
    chown -R --reference=$REPO_DIR $REPO_DIR
fi
