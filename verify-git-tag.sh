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

pushd $1 > /dev/null

if [ -n "$2" ]; then
	REF="$2"
else
	REF="HEAD"
fi

TAG=`git tag --contains=$REF | head -n 1`

if [ -z "$TAG" ]; then
	echo "Source is not tagged, cannot verify it!"
	exit 1
fi

git tag -v $TAG || exit 1

exit 0
