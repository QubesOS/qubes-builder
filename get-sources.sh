#!/bin/bash

# Configuration by env:
#  - GIT_BASEURL - base url of git repos
#  - GIT_SUBDIR - whose repo to clone
#  - GIT_SUFFIX - git component dir suffix (default .git)
#  - COMPONENT - component to clone
#  - BRANCH - git branch
#  - NO_CHECK=1 - disable signed tag checking
#  - CLEAN=1 - remove previous sources (use git up vs git clone)
#  - FETCH_ONLY=1 - fetch sources but do not merge
#  - GIT_REMOTE=<remote-name> - use "remote" from git configuration instead of
#    explicit URL
#  - REPO=dir - specify repository directory, component will be guessed based
#    on basename

set -e
[ "$DEBUG" = "1" ] && set -x

[ -n "$REPO" ] && COMPONENT="`basename $REPO`"

# Special case for qubes-builder itself
[ "$REPO" == "." ] && COMPONENT="qubes-builder"

[ -z "$COMPONENT" ] && { echo "ERROR: COMPONENT not set!"; exit 1; }

[ -z "$REPO" ] && REPO="$COMPONENT"

url_var="GIT_URL_${COMPONENT//-/_}"

if [ -n "${!url_var}" ]; then
    GIT_URL="${!url_var}"
else
    GIT_URL=$GIT_BASEURL/$GIT_SUBDIR/$COMPONENT$GIT_SUFFIX
fi

# Override GIT_URL with GIT_REMOTE if given
[ -n "$GIT_REMOTE" ] && GIT_URL=$GIT_REMOTE

branch_var="BRANCH_${COMPONENT//-/_}"

if [ -n "${!branch_var}" ]; then
    BRANCH="${!branch_var}"
fi

echo "-> Updateing sources for $COMPONENT..."
echo "--> Fetching from $GIT_URL $BRANCH..."
if [ "$REPO" == "." -o -d $REPO -a "$CLEAN" != '1' ]; then
    pushd $REPO > /dev/null
    git fetch -q $GIT_URL --tags || exit 1
    git fetch -q $GIT_URL $BRANCH || exit 1
    popd > /dev/null
    VERIFY_REF=FETCH_HEAD
else
    rm -rf $REPO
    git clone -q -b $BRANCH $GIT_URL $REPO
    VERIFY_REF=HEAD
fi

if ! [ "$NO_CHECK" == "1" ]; then
    echo "--> Verifying tags..."
    $SCRIPT_DIR/verify-git-tag.sh $REPO $VERIFY_REF || exit 1
fi

if [ "$FETCH_ONLY" != "1" ]; then

CURRENT_BRANCH=`cd $REPO; git branch | sed -n -e 's/^\* \(.*\)/\1/p'`
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
    pushd $REPO &> /dev/null
    red="`echo -e '\033[1;31m'`"
    green="`echo -e '\033[1;32m'`"
    normal="`echo -e '\033[0;0m'`"
    if [ -n "`git name-rev --name-only $BRANCH 2> /dev/null`" ]; then
        echo "--> Switching branch from $CURRENT_BRANCH branch to ${green}$BRANCH${normal}"
        git checkout $BRANCH || exit 1
    else
        echo -e "--> Switching branch from $CURRENT_BRANCH branch to new ${red}$BRANCH${normal}"
        git checkout FETCH_HEAD -b $BRANCH || exit 1
    fi
    popd &> /dev/null
fi

echo "--> Merging..."
[ "$VERIFY_REF" == "FETCH_HEAD" ] && ( cd $REPO; git merge --commit -q FETCH_HEAD; )

# For additionally download sources
if make -C $REPO -n get-sources verify-sources > /dev/null 2> /dev/null; then
    export GNUPGHOME="$PWD/keyrings/$COMPONENT"
    mkdir -p "$GNUPGHOME"
    chmod 700 "$GNUPGHOME"
    echo "--> Downloading additional sources for $COMPONENT..."
    make --quiet -C $REPO get-sources
    echo "--> Verifying the sources..."
    make --quiet -C $REPO verify-sources
fi
fi
echo
