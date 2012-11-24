#!/bin/sh

set -e

[ -z "$1" ] && { echo "Usage: $0 <dist>"; exit 1; }

REPO_DIR=$PWD/qubes-rpms-mirror-repo/$1

mkdir -p $REPO_DIR/rpm
createrepo -q $REPO_DIR
