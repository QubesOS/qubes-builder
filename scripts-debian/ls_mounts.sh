#!/bin/bash -e

#
# Written by Jason Mehring (nrgaway@gmail.com) 
# 
# Lists any mounts and processes within $1
#

ls_mounts() {
    MOUNTDIR="$1"

    if ! [[ "$MOUNTDIR" = /* ]]; then
        MOUNTDIR="${PWD}/${MOUNTDIR}"
    fi

    # Strip any extra trailing slashes ('/') from path if they exist
    # since we are doing an exact string match on the path
    MOUNTDIR=$(echo "$MOUNTDIR" | sed s#//*#/#g)

    echo "=== MOUNTS in ${MOUNTDIR}:"
    for dir in $(sudo grep "$MOUNTDIR" /proc/mounts | cut -f2 -d" " | sort -r | grep "^$MOUNTDIR")
    do
        echo "$dir"
    done

    echo "=== PROCESSES in ${MOUNTDIR}:"
    for dir in $(sudo grep "$MOUNTDIR" /proc/mounts | cut -f2 -d" " | sort -r | grep "^$MOUNTDIR")
    do
        processes=$(sudo lsof "$dir" 2> /dev/null | grep "$dir")
        if [ -z "$processes" ]; then
            echo "$processes"
        fi
    done
}


ls_mounts "$1"

