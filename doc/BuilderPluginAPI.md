Introduction
============

QubesBuilder is a framework to build Qubes system. The core part is responsible
for managing source code, verifying git tags and starting the build process.
But the code to actually build some packages/templates should be provided as a
plugin. Such single plugin can handle any of:
 - build a single binary package for given distribution
 - build template, including installing qubes-specific packages (this part is
   actually implemented in linux-template-builder)
 - provide additional configuration/modules (for example Whonix components)

Interface which should be provided by the plugin is described below


QubesBuilder
============

The purpose of this interface is to build binary packages for a single component.

The plugin should contain `Makefile.builder` file which is responsible for
exposing plugin parameters to QubesBuilder. The file will be included as a Makefile, with those variables available:
 * `COMPONENT` - name of current component to build
 * `DIST` - code name of target distribution
 * `PACKAGE_SET` - either "dom0" or "vm"
 * `SRC_DIR` - base directory with all the source code

If the combination of above variables is supported by the plugin (*only* then), it should set the following variables:
 * `DISTRIBUTION` - name of distribution
 * `BUILDER_MAKEFILE` - full path to a makefile for building packages for this distribution
   If the plugin is an overlay over other plugin, it can append itself to that variable.
   Filename there should be unique, because it can be copied to a common
   directory. It is a good idea to base filename on plugin name - for
   example Makefile.rpm, Makefile.debian

File pointed by `BUILDER_MAKEFILE` will be included after resolving all plugins
configuration and including component configuration (Makefile.builder there).
In addition to above variables, environment will contain:
 * `ORIG_SRC` - path to source code
 * `BUILDER_REPO_DIR` - full path to local packages repository for given
 distribution. Managing content of this directory is plugin resposibility.
 * `CHROOT_DIR` - fill path to a directory where plugin should setup build environment
 * `CACHEDIR` - full path to a directory for some plugin cache (for example downloaded packages)
 * `CHROOT_ENV` - environment variables which should be set during the build process
 * `OUTPUT_DIR` - directory name (relative to `ORIG_SRC`) where build products should be saved
 * `BUILD_LOG_URL` (optional) - URL to uploaded build log; this variable is available only for `update-repo` target and only when package(s) were just built

The `BUILDER_MAKEFILE` file should at lest set:
 * `PACKAGE_LIST` - (space separated) list of packages to build; it doesn't
 need to match output filenames in any way, it is just to support components
 with multiple output packages; this should be set based on settings provided
 by Makefile.build in component currently being built
 * `DIST_BUILD_DIR` - directory name relative to `CHROOT_DIR`, where source
 code directories should be created; QubesBuilder will copy the component
 source code to `DIST_BUILD_DIR/qubes-src/COMPONENT` and this path will be
 available in `DIST_SRC` variable

This makefile should define following targets:
 * `dist-prepare-chroot` - prepare build environment
 * `dist-prep` - do some source preparation (if needed)
 * `dist-build-dep` - install build dependencies for a given component (inside
   `CHROOT_DIR`); most likely will need also packages in
   `BUILDER_REPO_DIR`
 * `dist-package` - build the package
 * `dist-copy-out` - copy compiled package out of build environment; this
   target should move packages to `ORIG_SRC` (distro-specific subdir) and hardlink
   them to `BUILDER_REPO_DIR`
 * `update-repo` - copy/hardlink packages of given component to repository
   pointed by `UPDATE_REPO` variable; it should maintain metadata suitable for
   given distribution package manager; if `SNAPSHOT_FILE` is set, list of
   copied packages should be stored in that file (in any form usable later for
   `update-repo-from-snapshot` target); additionally `TARGET_REPO` variable is
   available with flavor of repository pointed by `UPDATE_REPO` (`current`,
   `current-testing`, etc)
 * `update-repo-from-snapshot` (optional) - copy/hardlink packages listed in
   `SNAPSHOT_FILE` (stored previously by `update-repo` target) to the
   repository pointed by `UPDATE_REPO` variable; this target may additionally
   use `SNAPSHOT_REPO` variable to know what was `TARGET_REPO` during snapshot
   creation (`update-repo` target call); additionally `TARGET_REPO` is also set
   to the flavor of repository pointed by `UPDATE_REPO`
 * `check-repo` (optional) - similar to `update-repo` but only check if package
   is already included in repository pointed by `UPDATE_REPO` variable; it
   should fail if package is not included

Targets `dist-build-dep`, `dist-package` and `dist-copy-out` will be executed
for each element of `PACKAGE_LIST` variable, with current element available in
`PACKAGE` variable.

Hint: you can get a full path to the plugin directory with this makefile
expression: `$(dir $(abspath $(lastword $(MAKEFILE_LIST))))`

Note that if files pointed out by `BUILDER_MAKEFILE` needs some additional files
to build the package (inside chroot), it needs to handle it in copy-in stage.
The `BUILDER_MAKEFILE` file(s) will be copied in generic-copy-in.

Take a look at `Makefile.generic` for details.

Template Builder
================

The purpose of this interface is to build qubes template root.img and default appmenus list.

The plugin should contain `Makefile.builder` file which is responsible for
exposing plugin parameters to linux-template builder. The file will be included as a Makefile, with those variables available:
 * `DIST` - code name of target distribution
 * `TEMPLATE_BUILDER=1` - to indicate that requested interface is for building the template

If the combination of above variables is supported by the plugin (*only* then), it should set the following variables:
 * `DISTRIBUTION` - name of distribution
 * `TEMPLATE_SCRIPTS` - full path to a directory with scripts for template-builder (see below)
    /or/
 * add new entries to `TEMPLATE_FLAVOR_DIR`
 * add entries to `TEMPLATE_ENV_WHITELIST` - environment variables (their names) that will be passed down to template build scripts (from `TEMPLATE_SCRIPTS` directory); this is useful for using configuration set in builder.conf (including custom options)

Hint: you can get a full path to the plugin directory with this makefile
expression: `$(dir $(abspath $(lastword $(MAKEFILE_LIST))))`

You should also refer to a file(s) using appropriate variable with full path to
the directory, because there is no guarantee from which directory the scripts
will be called.

The TemplateBuilder plugin should provide at least those scripts in `TEMPLATE_SCRIPTS` directory:
 * `00_prepare.sh` - preparation task, before even creating initial `root.img`
 * `01_install_core.sh` - install base system in directory pointed by
   `INSTALLDIR` - after this step it should be possible to run some programs
    (package manager for example) inside chroot
 * `02_install_groups.sh` - install full system according to selected flavor, but without Qubes-specific packages yet
 * `04_install_qubes.sh` - install Qubes-specific packages
 * `09_cleanup.sh` - cleanup after installation (purge caches, remove temporary files etc)

In addition to above script, at the end of build process, builder plugin should provide appmenus:
 * appmenus/netvm-whitelisted-appmenus.list - default application list for a NetVM based on this template
 * appmenus/vm-whitelisted-appmenus.list - default application list for an AppVM
 * appmenus/whitelisted-appmenus.list - default application list for the template itself

Above files can be dynamically generated by `04_install_qubes.sh` for example,
or provided statically. TemplateBuilder plugin can provide version
specific directories instead. TemplateBuilder will search for appmenus in
order:
 * `appmenus\_$DIST\_$TEMPLATE\_FLAVOR`
 * `appmenus\_$DIST`
 * `appmenus`

Variables available for TemplateBuilder scripts:
 - `TEMPLATE_NAME`
 - `DISTRIBUTION`
 - `DIST`
 - `CACHEDIR`
 - `INSTALLDIR` - target directory where the template OS should be installed; this is mounted root.img of the template, use chroot to run commands inside (when initial setup done)
 - `SCRIPTSDIR` - directory with plugin scripts (same as `TEMPLATE_SCRIPTS` set by Makefile.builder)
 - variables set in builder.conf and included in `TEMPLATE_ENV_WHITELIST`

