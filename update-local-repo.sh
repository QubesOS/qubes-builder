#!/bin/sh

set -e

REPO_DIR=$PWD/all-qubes-pkgs

mkdir -p $REPO_DIR/rpm

if ls qubes-src/*/rpm/*/*.rpm >/dev/null 2>&1; then
    ln -f qubes-src/*/rpm/*/*.rpm $REPO_DIR/rpm/
fi

createrepo -q --update $REPO_DIR
