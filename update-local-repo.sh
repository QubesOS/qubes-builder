#!/bin/sh

set -e

[ -z "$1" ] && { echo "Usage: $0 <dist>"; exit 1; }

REPO_DIR=$PWD/qubes-rpms-mirror-repo/$1
DIST=$1

KEYS_DIR="${PWD}/keys_${DISTRIBUTION}"

if [ -d $REPO_DIR/dists ]; then
    pushd $REPO_DIR
    mkdir -p dists/$DIST/main/binary-amd64
    dpkg-scanpackages --multiversion . > dists/$DIST/main/binary-amd64/Packages
    gzip -9c dists/$DIST/main/binary-amd64/Packages > dists/$DIST/main/binary-amd64/Packages.gz
    cat > dists/$DIST/Release <<EOF
Label: Qubes builder repo
Suite: $DIST
Codename: $DIST
Date: `date -R`
Architectures: amd64
Components: main
SHA1:
EOF
    function calc_sha1() {
        f=dists/$DIST/$1
        echo -n " "
        echo -n `sha1sum $f|cut -d' ' -f 1` ""
        echo -n `stat -c %s $f` ""
        echo $1
    }
    calc_sha1 main/binary-amd64/Packages >> dists/$1/Release
    calc_sha1 main/binary-amd64/Packages >> dists/$1/Release.gz

    rm -f dists/$DIST/Release.gpg
    gpg -abs --no-default-keyring \
        --secret-keyring $KEYS_DIR/$1-secring.gpg \
        --keyring $KEYS_DIR/$1-pubring.gpg \
        -o dists/$DIST/Release.gpg \
        dists/$DIST/Release
    popd
else
    mkdir -p $REPO_DIR/rpm
    createrepo --update -q $REPO_DIR
fi

if [ `id -u` -eq 0 ]; then
    chown -R --reference=$REPO_DIR $REPO_DIR
fi
