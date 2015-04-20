This repository contains an automated build system for Qubes, that downloads,
builds and packages all the Qubes components, and finally should spit out a
ready-to-use installation ISO.

In order to use it one should use an rpm-based distro, like Fedora,
and should ensure the following packages are installed:

* git
* createrepo
* rpm-build
* rpm-sign (if signing of build packages is enabled)
* rpmdevtools
* make 
* python-sh

Unusually one can install those packages by just issuing:

    $ sudo yum install git createrepo rpm-build make rpm-build make python-sh

Or just install them automatically by issuing:

    $ make install-deps

The build system creates build environments in chroots and so no other
packages are needed on the host. All files created by the build system
are contained within the qubes-builder directory. The full build
requires some 25GB of free space, so keep that in mind when deciding
where to place this directory.

The build system is configured via builder.conf file -- one should
copy selected file from example-configs/, and modify it as needed,
e.g.:

    cp example-configs/qubes-os-master.conf builder.conf 
    # edit the builder.conf file and set the following variables: 
    # GIT_PREFIX="marmarek/qubes-" 
    # NO_SIGN="1"

One additional useful requirement is that 'sudo root' work without any
prompt, which is default on most distros (e.g. 'sudo bash' brings you
the root shell without asking for any password). This is important as
the builder needs to switch to root and then back to user several
times during the build process (mainly to preform chroot). But do not call make
directly as root.

Additionally, if building with signing enabled (so NO\_SIGN is not
set), one must set `SIGN\_KEY` in builder.conf.

It is also recommended to use an empty passphrase for the private key
used for signing. Contrary to a popular belief, this doesn't affect
your key or sources security -- if somebody compromised your system,
then the game is over, whether you use additional passphrase for the
key or not.

To build all Qubes packages one would do:

    $ make qubes-os-iso

And this should produce a shiny new ISO.

One can also build selected component separately. E.g. to compile only
gui virtualization agent/daemon:

    $ make gui-daemon

You can also build the whole template in DispVM:

    $ make template-in-dispvm

For details see doc/ directory.
