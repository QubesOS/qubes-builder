#!/bin/sh

# Usage: $0 <source-dir> [<ref>]
# Example refs:
#  master
#  HEAD
#  mainstream/master
# Default ref: HEAD

if [ "$NO_CHECK" == "1" ]; then
	exit 0
fi

if [ -n "$KEYRING_DIR_GIT" ]; then
    export GNUPGHOME="`readlink -m $KEYRING_DIR_GIT`"
fi
pushd $1 > /dev/null

if [ -n "$2" ]; then
	REF="$2"
else
	REF="HEAD"
fi

TAG=`git tag --points-at=$REF | head -n 1`

if [ -z "$TAG" ]; then
	echo "Source is not tagged, cannot verify it!"
	exit 1
fi

git tag -v $TAG >/dev/null 2>/dev/null || { git tag -v $TAG; exit 1; }

exit 0
