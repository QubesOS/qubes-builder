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

### USE_QUBES_REPO_VERSION
> Default: no value

Use Qubes packages repository (yum.qubes-os.org/deb.qubes-os.org) to satisfy
build dependents. Set to target version of Qubes you are building packages for
(like "3.1", "3.2" etc).

This option allow to build a single component without building all required parts first.

### USE_QUBES_REPO_TESTING
> Default: no value

When used with `USE_QUBES_REPO_VERSION`, enable testing repository for that
version (in addition to stable). Set to "1" to enable this option.

Have no effect when `USE_QUBES_REPO_VERSION` is not set.

### ISO_INSTALLER
> Default: 1

When building 'iso' target, build installation iso.

### ISO_LIVE
> Default: 0

When building 'iso' target, build live image. Can be set together with
`ISO_INSTALLER` to build both.

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

Remove previous sources before getting new (use git pull vs git clone) - set "1" to use it

### NO_SIGN
> Default: no value

Disable signing of builded rpms - set "1" to use it

### SIGN_KEY
> Default: no value

set key used to sign packages

### UPDATE_REPO_CHECK_VTAG
> Default: no value

Set to "1" to enforce only version-tagged packages copied to updates repo
(update-repo-* targets).

### DEBUG
> Default: no value

print verbose messages about qubes-builder itself - set "1" to use it

### VERBOSE
> Default: 0

verbosity level of build process
* 0 - print almost no messages but all build process
* 1 - print (almost) only warnings
* 2 - full output

### NO_COLOR
> Default: no value

If set then various messages printed while building will not be colored.

### BUILDER_TURBO_MODE
> Default: 0

Speed up build process, can be at cost of data integrity if system fails during
build process (for example because of power failure). Currently supported only
by `builder-debian` plugin and it get rid of most fsync() calls.

### REPO_PROXY
> Default: no value

Use the specified http proxy for downloading packages from the network. This
can be used to speed up the process when the build environment is frequently
recreated. It should be set to the full URL of the proxy.

An example proxy setup is documented [here](./RepoProxy.md).

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

Github integration
------------------

### GITHUB_API_KEY
> Default: no value

Github API key having access to create/comment issues in:

* `$GITHUB_BUILD_ISSUES_REPO` repository (for reporting build failures)
* `$GITHUB_BUILD_REPORT_REPO` repository (for reporting all builds)
* any repository referenced in commit messages (see builder-github pluging)

### GITHUB_BUILD_ISSUES_REPO
> Default: no value

Github repository name (in for of `owner/name`) where build failures will be
reported (as github issues).

### GITHUB_BUILD_REPORT_REPO
> Default: no value

Github repository name (in for of `owner/name`) where all finished builds will
be reported (either successful or failed). The main purpose for this repository
is to track packages in 'current-testing' repository. Issues there can be
commented with GPG-signed command to move such package to 'current' repository
and close the issue.
This is implemented by builder-github pluging.

Example for using local git dirs as repo
========================================

    GIT_BASEURL=/home/user/qubes-src/
    GIT_PREFIX=
    GIT_SUFFIX=
