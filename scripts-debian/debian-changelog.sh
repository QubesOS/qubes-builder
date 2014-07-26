#!/bin/bash

debchange=`dirname $0`/debchange

v=`dpkg-parsechangelog | sed -n 's/^Version: //p'`

[ "`git describe`" == "v$v" ] && exit 0

release=0
if [[ "$v" == `cat version`?(devel*) ]]; then
    export DEBFULLNAME=`git config user.name`
    export DEBEMAIL=`git config user.email`
    $debchange --nomultimaint-merge --multimaint -ldevel -- 'Test build'
    $debchange --distribution=$DIST -r -- ''
    exit 0
else
    release=1
fi

IFS=%
git log --no-merges --topo-order --reverse --pretty=format:%an%%%ae%%%ad%%%s v$v..HEAD |\
    while read a_name a_email date sum; do
        export DEBFULLNAME="$a_name"
        export DEBEMAIL="$a_email"
        $debchange --newversion=`cat version` --no-auto-nmu --nomultimaint-merge --multimaint -- "$sum"
    done

if [ -n "$release" ]; then
    export DEBFULLNAME="`git log -n 1 --pretty=format:%an`"
    export DEBEMAIL="`git log -n 1 --pretty=format:%ae`"
    $debchange --distribution=$DIST -r -- ''
fi
