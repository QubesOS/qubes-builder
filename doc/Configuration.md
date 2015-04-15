Qubes builder configuration
===========================

Options available in builder.conf
### GIT_BASEURL
> Default: git://github.com

Base url of git repos

### GIT_PREFIX
> Default: no value

Which repo to clone. Can be used either to specify subdir
("qubes-r3/"), or real prefix ("QubesOS/qubes-")

### GIT_SUFFIX
> Default: .git

git component dir suffix

### BRANCH
> Default: master

git branch

### BRANCH_`component`
> Default: no value

Per component branch (override BRANCH).
Replace '-' with '_' in component name

### GIT_URL_`component`
> Default: no value

Custom git url for component (override other GIT_* vars)
Replace '-' with '_' in component name

### GIT_REMOTE
> Default: no value

track remote repository configured via "git remote". Mainly useful via cmdline:
make prepare-merge GIT_REMOTE="joanna"

### CHECK_BRANCH
> Default: no value (disabled)

check if the current branch is set to the one configured in
builder.conf before building the component. Set this to "1" to enable the feature

### COMPONENTS
> Default: see Makefile

Here you specify what you want to build. See example configs for sensible
lists. The order of components is important - it should reflect build
dependencies, otherwise build would fail.

### LINUX_INSTALLER_MULTIPLE_KERNELS
> Default: "no"

place all compiled linux kernels
(components linux-kernel*) on installation media
For details see http://wiki.qubes-os.org/trac/ticket/581
Available values: "yes" or "no"

### REMOTE_COMPONENTS_<git-remote>
> Default: no value

track only selected Qubes components for
given remote repository. Can be specified multiple times (for each remote).
Example:
REMOTE_COMPONENTS_joanna="core gui installer"

### DIST_DOM0
> Default: fc20

distribution for dom0 packages

### DISTS_VM
> Default: fc20

Distributions for VM packages (can be list - separate with space)
Supported distros: fc15 fc17 fc18 fc19 fc20 (depends on enabled plugins, see below)
Windows: win7x64 win7x86 winVistax64 winVistax86 winXPx64 winXPx86

This list can contain also flavors for template - appended after `+` sign. For example:
    DISTS_VM = wheezy+whonix-workstation

### BUILDER_PLUGINS
> Default: no value

qubes-builder and template-builder plugins (can be a list
- separate with space). You need to set the plugin(s) to be able to produce
any package - all the distribution-specific code is now in the plugins. For
base Qubes OS build you probably want to enable 'builder-fedora' plugin.
Note: you need to also add the plugin(s) to COMPONENTS, to have it
downloaded.

### BUILDER_PLUGINS_`dist`
> Default: no value

plugins enabled only for particular
distribution/version. For example:
BUILDER_PLUGINS_fc20 = builder-fedora

### BUILDER_TEMPLATE_CONF
> Default: no value

location of builder.conf to build a template. The
value is list of pairs <dist>:<location>, where <dist> can include a flavor
(e.g. fc20+minimal or wheezy+whonix-workstation). Location can be either local file path, or three parameters:
* GIT_URL - full URL to some git repo
* BRANCH - branch name
* KEY - path to local file with key(s) to verify tag on that repo
Those three parameters should be separated by comas. Example:
    BUILDER_TEMPLATE_CONF = fc20+minimal:https://github.com/username/reponame,master,/home/user/keys/username.asc

Repo should contain (at least) "config/builder.conf" file. This file (alone)
will be copied to qubes-builder, so it shouldn't rely directly on other files
in that repo. But can set for example URL to download builder plugins, or
even main builder modifications.

This setting is used only when building the template in DispVM
(template-in-dispvm target)

### QUBES_RELEASE
> Default: test-build

Set release version of result iso

### NO_CHECK
> Default: no value

Disable signed tag checking - set "1" to disable verify for everything or
can be a list of package names separated with spaces
Example:
    NO_CHECK=gui-agent-linux linux-template-builder

*Do not use this option unless you really understand what you are doing*. If
you want to handle your private fork, its better to sign the code and import
your key into keyring pointed by `KEYRING_DIR_GIT` option.

### KEYRING_DIR_GIT
> Default: keyrings/git

use separate keyring dir for git tags verification
This can be used to verify git tags with limited set of keys. If you want to
use your default keyring, set this to empty string.

### CLEAN
> Default: no value

Remove previous sources before getting new (use git up vs git clone) - set "1" to use it

### NO_SIGN
> Default: no value

Disable signing of builded rpms - set "1" to use it

### SIGN_KEY
> Default: no value

set key used to sign packages

### DEBUG
> Default: no value

print verbose messages about qubes-builder itself - set "1" to use it

### VERBOSE
> Default: 0

verbosity level of build process
* 0 - print almost no messages but all build process
* 1 - print (almost) only warnings
* 2 - full output

Windows specific settings
-------------------------

### WIN_CERT_FILENAME
Private key for signing files

### WIN_CERT_PASSWORD
Password for private key (if any)

## Only one of those:
### WIN_CERT_CROSS_CERT_FILENAME
Public certificate (if you have proper authenticode cert)

### WIN_CERT_PUBLIC_FILENAME
Public self-signed certificate (it will be generated if doesn't exists)

### WIN_BUILD_TYPE
Build type: fre (default) - release build, chk - debug build


Example for using local git dirs as repo
========================================

    GIT_BASEURL=/home/user/qubes-src/
    GIT_PREFIX=
    GIT_SUFFIX=
