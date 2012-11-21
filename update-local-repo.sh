#!/bin/sh

set -e

[ -z "$1" ] && { echo "Usage: $0 <dist>"; exit 1; }

REPO_DIR=$PWD/all-qubes-pkgs/$1

mkdir -p $REPO_DIR/rpm
createrepo -q --update $REPO_DIR
