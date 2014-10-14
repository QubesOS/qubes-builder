``#!/bin/bash -e

#
# Written by Jason Mehring (nrgaway@gmail.com) 
# 
INSTALLDIR="$(readlink -m mnt)"
# Kills any processes within the mounted location and 
# unmounts any mounts active within.
# 
# To keep the actual mount mounted, add a '/' to end
#
# $1: directory to umount
#
# Examples:
# To kill all processes and mounts within 'chroot-jessie' but keep
# 'chroot-jessie' mounted:
#
# ./umount_kill.sh chroot-jessie/ 
#
# To kill all processes and mounts within 'chroot-jessie' AND also
# umount 'chroot-jessie' mount:
#
# ./umount_kill.sh chroot-jessie
# 

# $1 = full path to mount; 
# $2 = if set will not umount; only kill processes in mount
umount_kill() {
    MOUNTDIR="$1"

    # We need absolute paths here so we don't kill everything
    if ! [[ "$MOUNTDIR" = /* ]]; then
        MOUNTDIR="${PWD}/${MOUNTDIR}"
    fi

    # Strip any extra trailing slashes ('/') from path if they exist
    # since we are doing an exact string match on the path
    MOUNTDIR=$(echo "$MOUNTDIR" | sed s#//*#/#g)

    echo "-> Attempting to kill any processes still running in '$MOUNTDIR' before un-mounting"
    for dir in $(sudo grep "$MOUNTDIR" /proc/mounts | cut -f2 -d" " | sort -r | grep "^$MOUNTDIR")
    do
        sudo lsof "$dir" 2> /dev/null | \
            grep "$dir" | \
            tail -n +2 | \
            awk '{print $2}' | \
            xargs --no-run-if-empty sudo kill -9

        echo "un-mounting $dir"
        if ! [ "$2" ] && $(mountpoint -q "$dir"); then
            sudo umount -n "$dir" 2> /dev/null || \
                sudo umount -n -l "$dir" 2> /dev/null || \
                echo "umount $dir unsuccessful!"
        fi
    done
}

kill_processes_in_mount() {
    umount_kill $1 "false" || :
}

if [ $(basename "$0") == "umount_kill.sh" -a "$1" ]; then
    umount_kill "$1"
fi
