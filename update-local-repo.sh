#!/bin/sh

set -e

REPO_DIR=$PWD/all-qubes-pkgs

mkdir -p $REPO_DIR/rpm

ln -f qubes-src/*/rpm/*/*.rpm $REPO_DIR/rpm/

createrepo --update $REPO_DIR                         
