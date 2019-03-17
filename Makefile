.DEFAULT_GOAL = help

# Force bash for some advanced substitution (eg ${!...})
SHELL = /bin/bash

SRC_DIR := qubes-src
BUILDER_DIR := $(shell readlink -m $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

#Include config file
BUILDERCONF ?= builder.conf
-include $(BUILDERCONF)

# Set defaults
BRANCH ?= master
GIT_BASEURL ?= git://github.com
GIT_SUFFIX ?= .git
DIST_DOM0 ?= fc20
DISTS_VM ?= fc20
VERBOSE ?= 0

# Beware of build order
COMPONENTS ?= builder

LINUX_REPO_BASEDIR ?= $(SRC_DIR)/linux-yum/current-release
# set default RELEASE based on LINUX_REPO_BASEDIR, assuming it was set to
# something sensible (not the value above)
RELEASE ?= $(patsubst r%,%,$(lastword $(subst /, ,$(LINUX_REPO_BASEDIR))))
INSTALLER_COMPONENT ?= installer-qubes-os
BACKEND_VMM ?= xen
KEYRING_DIR_GIT ?= $(BUILDER_DIR)/keyrings/git

TESTING_DAYS = 7

ifdef GIT_SUBDIR
  GIT_PREFIX ?= $(GIT_SUBDIR)/
endif

# checking for make from Makefile is pointless
DEPENDENCIES ?= git rpmdevtools rpm-build createrepo python2-sh wget perl-Digest-MD5 perl-Digest-SHA

ifneq (1,$(NO_SIGN))
  DEPENDENCIES += rpm-sign
endif

BUILDER_PLUGINS_DISTS :=
_dist = $(word 1,$(subst +, ,$(_dist_vm)))
_plugin = $(BUILDER_PLUGINS_$(_dist))
BUILDER_PLUGINS_DISTS += $(strip $(foreach _dist_vm, $(DISTS_VM), $(_plugin)))

# Used to track automatically modified values
_ORIGINAL_DISTS_VM := $(DISTS_VM)
_ORIGINAL_DISTS_ALL := $(DISTS_ALL)
_ORIGINAL_BUILDER_PLUGINS := $(BUILDER_PLUGINS) $(BUILDER_PLUGINS_DISTS)
_ORIGINAL_COMPONENTS := $(COMPONENTS)
_ORIGINAL_TEMPLATE := $(TEMPLATE)
_ORIGINAL_TEMPLATE_FLAVOR := $(TEMPLATE_FLAVOR)
_ORIGINAL_TEMPLATE_ALIAS := $(TEMPLATE_ALIAS)
_ORIGINAL_TEMPLATE_LABEL := $(TEMPLATE_LABEL)
_ORIGINAL_TEMPLATE_FLAVOR_DIR := $(TEMPLATE_FLAVOR_DIR)

# Apply aliases and add TEMPLATE_LABEL if it does not already exist
_alias_name = $(word 1,$(subst :, ,$(_alias)))
_alias_flavor = $(word 2,$(subst :, ,$(_alias)))
_template_name = $(subst +,-,$(_alias_name))
_aliases = $(eval DISTS_VM := $(patsubst $(_alias_name), $(_alias_flavor), $(DISTS_VM))) \
          $(if $(filter $(_alias_flavor):$(_template_name), $(TEMPLATE_LABEL)),, \
              $(eval TEMPLATE_LABEL += $(_alias_flavor):$(_template_name)) \
          )
$(strip $(foreach _alias, $(TEMPLATE_ALIAS), $(_aliases)))

# Sets the COMPONENTS to only what is needed to build the template
ifeq ($(TEMPLATE_ONLY), 1)
  COMPONENTS := $(TEMPLATE)
  DIST_DOM0 :=
endif

COMPONENTS_NO_BUILDER := $(filter-out builder,$(COMPONENTS))
COMPONENTS_NO_TPL_BUILDER := $(filter-out linux-template-builder builder,$(COMPONENTS))

# The package manager used to install dependencies. builder.conf
# files may depend on this variable to determine the correct
# dependency names.
PKG_MANAGER ?= $(if $(wildcard /etc/debian_version),dpkg,rpm)

# Include any BUILDER_PLUGINS builder.conf configurations
BUILDER_PLUGINS_ALL := $(BUILDER_PLUGINS) $(BUILDER_PLUGINS_DISTS)
-include $(BUILDER_PLUGINS:%=$(SRC_DIR)/%/builder.conf)
-include $(BUILDER_PLUGINS_DISTS:%=$(SRC_DIR)/%/builder.conf)

# Remove any unused labels
ifneq "$(SETUP_MODE)" "1"
  _template_flavor = $(word 1,$(subst :, ,$(_LABEL)))
  _template_name = $(word 2,$(subst :, ,$(_LABEL)))
  _labels = $(filter $(filter $(_template_flavor), $(DISTS_VM)):$(_template_name), $(_LABEL))
  TEMPLATE_LABEL := $(strip $(foreach _LABEL, $(TEMPLATE_LABEL), $(_labels)))
endif

# Get rid of quotes
DISTS_VM := $(shell echo $(DISTS_VM))
NO_CHECK := $(shell echo $(NO_CHECK))
TEMPLATE_FLAVOR := $(shell echo $(TEMPLATE_FLAVOR))
DEPENDENCIES := $(sort $(DEPENDENCIES))

DISTS_VM_NO_FLAVOR := $(sort $(foreach _dist, $(DISTS_VM), \
	$(firstword $(subst +, ,$(_dist)))))

DISTS_ALL := $(sort $(DIST_DOM0:%=dom0-%) $(DISTS_VM_NO_FLAVOR:%=vm-%))

GIT_REPOS := $(COMPONENTS_NO_BUILDER:%=$(SRC_DIR)/%)

ifneq (,$(findstring builder,$(COMPONENTS)))
GIT_REPOS += .
endif

check_branch = if [ -n "$(1)" -a "0$(CHECK_BRANCH)" -ne 0 ]; then \
				   BRANCH=$(BRANCH); \
				   branch_var="BRANCH_$(subst -,_,$(1))"; \
				   [ -n "$${!branch_var}" ] && BRANCH="$${!branch_var}"; \
				   pushd $(SRC_DIR)/$(1) > /dev/null; \
				   CURRENT_BRANCH=`git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --exact-match HEAD`; \
				   if [ "$$BRANCH" != "$$CURRENT_BRANCH" ]; then \
					   echo "-> ERROR: Wrong branch $$branch_var=$$CURRENT_BRANCH (expected $$BRANCH)"; \
					   exit 1; \
				   fi; \
				   popd > /dev/null; \
			   fi

ifndef NO_COLOR
.colors.mk: Makefile
	@echo "c.bold   := $$(tput bold    2>/dev/null || tput md 2>/dev/null)" >$@
	@echo "c.normal := $$(tput sgr0    2>/dev/null || tput me 2>/dev/null)" >>$@
	@echo "c.black  := $$(tput setaf 0 2>/dev/null || tput AF 0 2>/dev/null)" >>$@
	@echo "c.red    := $$(tput setaf 1 2>/dev/null || tput AF 1 2>/dev/null)" >>$@
	@echo "c.green  := $$(tput setaf 2 2>/dev/null || tput AF 2 2>/dev/null)" >>$@
	@echo "c.blue   := $$(tput setaf 4 2>/dev/null || tput AF 4 2>/dev/null)" >>$@
	@echo "c.white  := $$(tput setaf 7 2>/dev/null || tput AF 7 2>/dev/null)" >>$@
-include .colors.mk
-include .user_colors.mk
endif

.EXPORT_ALL_VARIABLES:
.ONESHELL:
help:
	@echo "make qubes            -- download and build all components"
	@echo "make qubes-dom0       -- download and build all dom0 components"
	@echo "make qubes-vm         -- download and build all VM components"
	@echo "make template-in-dispvm -- start new DispVM and build the whole template there"
	@echo "make get-sources      -- download/update all sources (including source tarballs)"
	@echo "make get-sources-extra -- download source tarballs required for some components"
	@echo "make iso              -- update installer repos, make iso"
	@echo "make qubes-os-iso     -- same as \"make get-sources qubes sign-all iso\""
	@echo "make build-info       -- show current build options"
	@echo "make build-id         -- show current sources (output suitable for builder.conf to repeat the same build)"
	@echo "make about            -- show all included Makefiles"
	@echo "make sign-all         -- sign all packages"
	@echo "make sign-vm          -- sign all VM packages"
	@echo "make sign-dom0        -- sign all Dom0 packages"
	@echo "make clean-all        -- remove any downloaded sources and built packages"
	@echo "make clean-rpms       -- remove any built packages"
	@echo "make clean-chroot     -- remove all chroot directories"
	@echo "make mostlyclean      -- remove built packages and built templates"
	@echo "make distclean        -- remove all files and directories built or added"
	@echo "make check            -- check for any uncommited changes and unsigned tags"
	@echo "make check-depend     -- check for build dependencies ($(DEPENDENCIES))"
	@echo "make install-deps     -- install missing build dependencies ($(DEPENDENCIES))"
	@echo "make diff             -- show diffs for any uncommitted changes"
	@echo "make show REF=git_ref -- show git object git_ref regardless of what repo it's in"
	@echo "make grep RE=regexp   -- grep for regexp in all components"
	@echo "make push             -- do git push for all repos, including tags"
	@echo "make show-vtags       -- list components version tags (only when HEAD have such) and branches"
	@echo "make check-release-status -- check whether packages are included in updates repository"
	@echo "make show-authors     -- list authors of Qubes code based on commit log of each component"
	@echo "make prepare-merge    -- fetch the sources from git, but only show new commits instead of merging"
	@echo "make show-unmerged    -- list fetched but unmerged commits (see make prepare-merge)"
	@echo "make do-merge         -- merge fetched commits"
	@echo "make switch-branch    -- checkout branch listed in builder.conf for each component"
	@echo "make update-repo-*    -- copy binary packages to the updates repository (yum/apt/...)"
	@echo "make get-var GET_VAR=... -- print content of requested configuration variable"
	@echo "make add-remote       -- add remote git repository"
	@echo "make COMPONENT        -- build both dom0 and VM part of COMPONENT"
	@echo "make COMPONENT-dom0   -- build only dom0 part of COMPONENT"
	@echo "make COMPONENT-vm     -- build only VM part of COMPONENT"
	@echo "COMPONENT can be one of:"
	@echo "  $(COMPONENTS)"
	@echo ""
	@echo "You can also specify COMPONENTS=\"c1 c2 c3 ...\" on command line"
	@echo "to operate on subset of components. Example: make COMPONENTS=\"gui\" get-sources"


get-sources-sort = $(filter $(BUILDER_PLUGINS), $(COMPONENTS)) $(filter-out $(BUILDER_PLUGINS), $(COMPONENTS_NO_BUILDER))
get-sources-tgt = $(get-sources-sort:%=%.get-sources)
get-sources-extra-tgt = $(get-sources-sort:%=%.get-sources-extra)
.PHONY: get-sources builder.get-sources $(get-sources-tgt) $(get-sources-extra-tgt)
$(get-sources-tgt): build-info
	@REPO=$(@:%.get-sources=$(SRC_DIR)/%) MAKE="$(MAKE)" $(BUILDER_DIR)/scripts/get-sources
$(get-sources-extra-tgt):
	@REPO=$(@:%.get-sources-extra=$(SRC_DIR)/%) MAKE="$(MAKE)" $(BUILDER_DIR)/scripts/get-sources-extra
builder.get-sources: build-info
	@REPO=. MAKE="$(MAKE)" $(BUILDER_DIR)/scripts/get-sources
get-sources: $(BUILDERCONF) $(filter builder.get-sources, $(COMPONENTS:%=%.get-sources)) $(get-sources-tgt) get-sources-extra
get-sources-extra: $(get-sources-extra-tgt)

.PHONY: check.rpm check.dpkg check-depend check-depend.rpm check-depend.dpkg
check.rpm: $(if $(shell which rpm 2>/dev/null), /bin/true, please.install.rpm.and.try.again);
check.dpkg: $(if $(shell which dpkg 2>/dev/null), /bin/true, please.install.dpkg.and.try.again);
check-depend.rpm:
	@echo "Currently installed dependencies:" && rpm -q --whatprovides $(DEPENDENCIES) || \
		{ echo "ERROR: call 'make install-deps' to install missing dependencies"; exit 1; }
check-depend.dpkg:
	@test $$(dpkg -l $(DEPENDENCIES) | tail -n +5 | grep '^i' | wc -l) -eq $(words $(DEPENDENCIES)) || \
		{ echo "ERROR: call 'make install-deps' to install missing dependencies"; exit 1; }
check-depend: check.$(PKG_MANAGER) check-depend.$(PKG_MANAGER)

$(COMPONENTS_NO_TPL_BUILDER): % : %-dom0 %-vm

$(COMPONENTS_NO_TPL_BUILDER:%=%-vm) : %-vm : check-depend
	@$(call check_branch,$*)
	@if [ -r $(SRC_DIR)/$*/Makefile.builder ]; then \
		for DIST in $(DISTS_VM_NO_FLAVOR); do \
			$(MAKE) --no-print-directory DIST=$$DIST PACKAGE_SET=vm COMPONENT=$* ENV_COMPONENT=$(ENV_$(subst -,_,$*)) -f Makefile.generic all || exit 1; \
		done; \
	elif [ -n "`$(MAKE) -n -s -C $(SRC_DIR)/$* rpms-vm 2> /dev/null`" ]; then \
	    for DIST in $(DISTS_VM_NO_FLAVOR); do \
	        MAKE_TARGET="rpms-vm" ./scripts/build $$DIST $* || exit 1; \
	    done; \
	fi

$(COMPONENTS_NO_TPL_BUILDER:%=%-dom0) : %-dom0 : check-depend
	@$(call check_branch,$*)
ifneq ($(DIST_DOM0),)
	@if [ -r $(SRC_DIR)/$*/Makefile.builder ]; then \
		$(MAKE) -f Makefile.generic DIST=$(DIST_DOM0) PACKAGE_SET=dom0 COMPONENT=$* ENV_COMPONENT=$(ENV_$(subst -,_,$*)) all || exit 1; \
	elif [ -n "`$(MAKE) -n -s -C $(SRC_DIR)/$* rpms-dom0 2> /dev/null`" ]; then \
	    MAKE_TARGET="rpms-dom0" ./scripts/build $(DIST_DOM0) $* || exit 1; \
	fi
endif

.PHONY: $(COMPONENTS:%=sign.%)
$(COMPONENTS:%=sign.%): sign.% : sign.dom0.% sign.vm.%

.PHONY: $(COMPONENTS:%=sign.dom0.%)
ifneq ($(DIST_DOM0),)
$(COMPONENTS:%=sign.dom0.%): sign.dom0.% : sign.dom0.$(DIST_DOM0).%
endif

.PHONY: $(COMPONENTS:%=sign.vm.%)
$(COMPONENTS_NO_TPL_BUILDER:%=sign.vm.%): sign.vm.% : $(addsuffix .%, $(DISTS_VM_NO_FLAVOR:%=sign.vm.%))
# don't strip flavors for template signing
sign.vm.linux-template-builder : $(addsuffix .linux-template-builder, $(DISTS_VM:%=sign.vm.%))

sign.%: PACKAGE_SET = $(word 1, $(subst ., ,$*))
sign.%: DIST        = $(word 2, $(subst ., ,$*))
sign.%: _space      = $(_empty) $(_empty)
sign.%: COMPONENT   = $(word 3, $(subst ., ,$*))
sign.%: $(SRC_DIR)/$(COMPONENT)
sign.%:
	@$(call check_branch,$(COMPONENT))
	@SIGN_KEY=$(SIGN_KEY); \
	sign_key_var="SIGN_KEY_$${DIST%%+*}"; \
	[ -n "$${!sign_key_var}" ] && SIGN_KEY="$${!sign_key_var}"; \
	if [ "$(COMPONENT)" = linux-template-builder ]; then
		export TEMPLATE_NAME=$$(MAKEFLAGS= make -s \
				-C $(SRC_DIR)/linux-template-builder \
				DIST=$(DIST) \
				template-name)
	fi
	if [ -r $(SRC_DIR)/$(COMPONENT)/Makefile.builder ]; then \
		$(MAKE) --no-print-directory -f Makefile.generic \
			DIST=$(DIST) \
			PACKAGE_SET=$(PACKAGE_SET) \
			COMPONENT=$(COMPONENT) \
			SIGN_KEY=$$SIGN_KEY \
			sign || exit 1; \
	elif [ -d $(SRC_DIR)/$(COMPONENT)/rpm ]; then \
		# Old mechanism supported only for RPM
		FILE_LIST=""; for RPM in $(SRC_DIR)/$(COMPONENT)/rpm/*/*.rpm; do \
			if ! $(SRC_DIR)/$(INSTALLER_COMPONENT)/rpm_verify $$RPM > /dev/null; then \
				FILE_LIST="$$FILE_LIST $$RPM" ;\
			fi ;\
		done ; \
		if [ -n "$$FILE_LIST" ]; then \
			echo "--> Signing..."; \
			RPMSIGN_OPTS=--digest-algo=sha256; \
			if [ -n "$$SIGN_KEY" ]; then \
				RPMSIGN_OPTS="--key-id=$$SIGN_KEY"; \
			fi; \
			setsid -w rpmsign "$$RPMSIGN_OPTS" --addsign $$FILE_LIST </dev/null ;\
		fi; \
	fi

# With generic rule it isn't handled correctly (xfce4-dom0 target isn't built
# from xfce4 repo...). "Empty" rule because real package are built by above
# generic rule as xfce4-dom0-dom0
xfce4-dom0:
	@true

# Nothing to be done there
yum-dom0 yum-vm:
	@true

# Some components requires custom rules

linux-template-builder:: template

template:: $(DISTS_VM:%=template-local-%)

# Allow template flavors to be declared within the DISTS_VM declaration
# <distro>+<template flavor>+<template options>+<template options>...
template-local-%::
	@DIST=$*; \
	dist_array=($${DIST//+/ }); \
	DIST=$${dist_array[0]}; \
	TEMPLATE_FLAVOR=$${dist_array[1]}; \
	TEMPLATE_OPTIONS="$${dist_array[@]:2}"; \
	plugins_var="BUILDER_PLUGINS_$$DIST"; \
	BUILDER_PLUGINS_COMBINED="$(BUILDER_PLUGINS) $${!plugins_var}"; \
	BUILDER_PLUGINS_DIRS=`for d in $$BUILDER_PLUGINS_COMBINED; do echo -n " $(BUILDER_DIR)/$(SRC_DIR)/$$d"; done`; \
	export BUILDER_PLUGINS_DIRS; \
	export TEMPLATE_FLAVOR_DIR; \
	CACHEDIR=$(BUILDER_DIR)/cache/$$DIST; \
	export CACHEDIR; \
	MAKE_TARGET=rpms; \
	if [ "0$(TEMPLATE_ROOT_IMG_ONLY)" -eq "1" ]; then \
		MAKE_TARGET=rootimg-build; \
	fi; \
	export GNUPGHOME="$(BUILDER_DIR)/keyrings/template-$$DIST"; \
	mkdir -m 700 -p "$$GNUPGHOME"; \
	export DIST NO_SIGN TEMPLATE_FLAVOR TEMPLATE_OPTIONS; \
	$(MAKE) -s -C $(SRC_DIR)/linux-template-builder prepare-repo-template || exit 1; \
	for repo in $(GIT_REPOS); do \
		if [ "$$repo" = "$(SRC_DIR)/linux-template-builder" ]; then \
			continue; \
		fi; \
		if [ -r $$repo/Makefile.builder ]; then \
			$(MAKE) --no-print-directory -f Makefile.generic \
				PACKAGE_SET=vm \
				COMPONENT=`basename $$repo` \
				UPDATE_REPO=$(BUILDER_DIR)/$(SRC_DIR)/linux-template-builder/pkgs-for-template/$$DIST \
				update-repo || exit 1; \
		elif $(MAKE) -C $$repo -n update-repo-template > /dev/null 2> /dev/null; then \
			$(MAKE) -s -C $$repo update-repo-template || exit 1; \
		fi; \
	done; \
	if [ "$(VERBOSE)" -eq 0 ]; then \
		echo "-> Building template $$DIST (logfile: build-logs/template-$$DIST.log)..."; \
		$(MAKE) -s -C $(SRC_DIR)/linux-template-builder $$MAKE_TARGET > build-logs/template-$$DIST.log 2>&1 || exit 1; \
		echo "--> Done."; \
	else \
		$(MAKE) -s -C $(SRC_DIR)/linux-template-builder $$MAKE_TARGET || exit 1; \
	fi

template-github: template-github.token $(DISTS_VM:%=template-github-%)

template-github.token:
	@if [ "x$(GITHUB_API_KEY)" != "x" ]; then \
		echo "machine api.github.com login $(GITHUB_API_KEY) password x-oauth-basic" > $(BUILDER_DIR)/.netrc_github
	else \
		echo "Please provide GITHUB_API_KEY."; exit 1; \
	fi

template-github-%: DIST=$*
template-github-%: GITHUB_API_FILE=$(BUILDER_DIR)/.netrc_github
template-github-%:
	@if [ "$(VERBOSE)" -eq 0 ]; then \
		echo "-> Posting build command for template $$DIST (logfile: build-logs/template-github-$$DIST.log)..."; \
		$(BUILDER_DIR)/scripts/generate_build_github.sh $(DIST) > build-logs/template-github-$$DIST.log 2>&1 || exit 1; \
		echo "--> Done."; \
	else \
		$(BUILDER_DIR)/scripts/generate_build_github.sh $(DIST) || exit 1; \
	fi;\

template-in-dispvm: $(DISTS_VM:%=template-in-dispvm-%)

template-in-dispvm-%: DIST=$*
template-in-dispvm-%: BUILD_LOG=build-logs/template-$(DIST).log
template-in-dispvm-%:
	@BUILDER_TEMPLATE_CONF=$(lastword $(filter $(DIST):%,$(BUILDER_TEMPLATE_CONF))); \
	if [ -e "$(BUILD_LOG)" ]; then\
		mv -f "$(BUILD_LOG)" "$(BUILD_LOG).old";\
	fi
	echo "-> Building template $(DIST) (logfile: $(BUILD_LOG))..."; \
	if [ $(VERBOSE) -eq 0 ]; then\
		./scripts/build_full_template_in_dispvm $(DIST) "$${BUILDER_TEMPLATE_CONF#*:}" >> $(BUILD_LOG) 2>&1 || exit 1
	else\
		set -o pipefail; \
		{ ./scripts/build_full_template_in_dispvm $(DIST) "$${BUILDER_TEMPLATE_CONF#*:}" 2>&1 || exit 1; } | tee -a $(BUILD_LOG)
	fi

# Sign only unsigned files (naturally we don't expect files with WRONG sigs to be here)
COMPONENTS_TO_SIGN := $(if $(NO_SIGN),,$(COMPONENTS))
.PHONY: sign-all sign-dom0 sign-vm
sign-all:: $(COMPONENTS_TO_SIGN:%=sign.%);
sign-dom0:: $(COMPONENTS_TO_SIGN:%=sign.dom0.%);
sign-vm:: $(COMPONENTS_TO_SIGN:%=sign.vm.%);

qubes:: build-info $(COMPONENTS_NO_BUILDER)

qubes-dom0:: build-info
qubes-dom0:: $(addsuffix -dom0,$(COMPONENTS_NO_TPL_BUILDER))

qubes-vm:: build-info
qubes-vm:: $(addsuffix -vm,$(COMPONENTS_NO_TPL_BUILDER))

qubes-os-iso: get-sources qubes sign-all iso

.PHONY: clean-installer-rpms clean-rpms
clean-installer-rpms:
	(cd $(SRC_DIR)/$(INSTALLER_COMPONENT)/yum || cd $(SRC_DIR)/$(INSTALLER_COMPONENT)/yum && ./clean_repos.sh) || true

clean-rpms:: clean-installer-rpms
	@for dist in $(DISTS_ALL); do \
		echo "Cleaning up rpms in qubes-packages-mirror-repo/$$dist/..."; \
		sudo rm -rf qubes-packages-mirror-repo/$$dist || true ;\
	done
	@echo 'Cleaning up rpms in $(SRC_DIR)/*/pkgs/*/*/*...'
	@sudo rm -f $(SRC_DIR)/*/pkgs/*/*/*.rpm || true

clean-makefiles = $(filter-out ./Makefile,$(wildcard $(GIT_REPOS:%=%/Makefile)))
clean-tgt = $(filter-out linux-template-builder.clean,$(clean-makefiles:$(SRC_DIR)/%/Makefile=%.clean))
clean-builder-tgt = $(DISTS_VM_NO_FLAVOR:%=linux-template-builder.clean.%)
.PHONY: clean $(clean-tgt) $(clean-builder-tgt)
$(clean-tgt):
	@-$(MAKE) -s -i -k -C $(SRC_DIR)/$(@:%.clean=% clean)
$(clean-builder-tgt):
	if [ -d $(SRC_DIR)/linux-template-builder ]; then
		@-DIST=$(subst .,,$(suffix $@)) $(MAKE) -s -i -k -C $(SRC_DIR)/linux-template-builder clean
	fi
clean:: $(clean-tgt) $(clean-builder-tgt);

clean-chroot-tgt = $(DISTS_ALL:%=chroot-%.clean)
.PHONY: clean-chroot $(clean-chroot-tgt)
$(clean-chroot-tgt): %.clean : %.umount
	@sudo rm -rf $(BUILDER_DIR)/$(@:%.clean=%)
clean-chroot: $(clean-chroot-tgt)

.PHONY: clean-all
clean-all: clean-chroot clean-rpms clean
	@sudo rm -rf $(SRC_DIR)

.PHONY: distclean
distclean: clean-all
	sudo rm -rf $(BUILDER_DIR)/cache/*
	sudo rm -rf $(BUILDER_DIR)/iso/*
	sudo rm -rf $(BUILDER_DIR)/build-logs/*
	sudo rm -rf $(BUILDER_DIR)/repo-latest-snapshot/*
	sudo rm -rf $(BUILDER_DIR)/builder.conf*
	sudo rm -rf $(BUILDER_DIR)/keyrings
	sudo rm -f $(BUILDER_DIR)/.*.mk
	find $(BUILDER_DIR)/qubes-packages-mirror-repo/* -maxdepth 0 -type d -exec rm -rf {} \;

# Does a regular clean as well as removes all prepared and created template
# images as well as chroot-* while leaving source repos in qubes-src
.PHONY: mostlyclean
mostlyclean:: _linux_template_builder := $(BUILDER_DIR)/$(SRC_DIR)/linux-template-builder
mostlyclean:: clean-chroot clean-rpms clean
	if [ -d "$(_linux_template_builder)" ] ; then \
	    pushd "$(_linux_template_builder)"; \
	    sudo $(BUILDER_DIR)/scripts/umount_kill.sh mnt; \
	    sudo rm -rf prepared_images/*  || true; \
	    sudo rm -rf qubeized_images/*  || true; \
	    sudo rm -rf rpm/noarch/*  || true; \
	    sudo rm -rf pkgs-for-template/* || true; \
	    popd; \
	fi

.PHONY: iso iso.clean-repos iso.copy-rpms iso.copy-template-rpms
iso.clean-repos:
	@echo "-> Preparing for ISO build..."
	@$(MAKE) -s -C $(SRC_DIR)/$(INSTALLER_COMPONENT) clean-repos

iso.copy-rpms: $(COMPONENTS_NO_TPL_BUILDER:%=iso.copy-rpms.%)

iso.copy-rpms.%: COMPONENT=$*
iso.copy-rpms.%: REPO=$(SRC_DIR)/$(COMPONENT)
iso.copy-rpms.%: $(SRC_DIR)/%/Makefile.builder
	@echo "--> Copying $(COMPONENT) RPMs..."
	@$(MAKE) --no-print-directory -f Makefile.generic \
		PACKAGE_SET=dom0 \
		DIST=$(DIST_DOM0) \
		COMPONENT=$(COMPONENT) \
		UPDATE_REPO=$(BUILDER_DIR)/$(SRC_DIR)/$(INSTALLER_COMPONENT)/yum/qubes-dom0 \
		update-repo

iso.copy-rpms.%: $(SRC_DIR)/%/Makefile
	@echo "--> Copying $(COMPONENT) RPMs..."
	if $(MAKE) -s -C $(REPO) -n update-repo-installer > /dev/null 2> /dev/null; then \
		if ! $(MAKE) -s -C $(REPO) update-repo-installer ; then \
			echo "make update-repo-installer failed for $(COMPONENT)"; \
			exit 1; \
	    fi; \
	fi

iso.copy-template-rpms: $(DISTS_VM:%=iso.copy-template-rpms.%)

iso.copy-template-rpms.%: DIST=$*

iso.copy-template-rpms.%: $(SRC_DIR)/linux-template-builder/Makefile.builder
	@echo "--> Copying template $(DIST) RPM..."
	@export TEMPLATE_NAME=$$(MAKEFLAGS= make -s \
			-C $(SRC_DIR)/linux-template-builder \
			DIST=$(DIST) \
			template-name); \
	$(MAKE) --no-print-directory -f Makefile.generic \
		PACKAGE_SET=vm \
		DIST=$(DIST) \
		COMPONENT=linux-template-builder \
		UPDATE_REPO=$(BUILDER_DIR)/$(SRC_DIR)/$(INSTALLER_COMPONENT)/yum/qubes-dom0 \
		update-repo

iso.copy-template-rpms.%: $(SRC_DIR)/linux-template-builder/Makefile
	@echo "--> Copying template $(DIST) RPM..."
	@if ! DIST=$(DIST) UPDATE_REPO=$(BUILDER_DIR)/$(SRC_DIR)/$(INSTALLER_COMPONENT)/yum/qubes-dom0 \
		DIST=$(DIST) $(MAKE) -s -C $(SRC_DIR)/linux-template-builder update-repo-installer ; then \
			echo "make update-repo-installer failed for template dist=$$DIST"; \
			exit 1; \
	fi

iso: iso.clean-repos iso.copy-rpms iso.copy-template-rpms
	@if [ "$(LINUX_INSTALLER_MULTIPLE_KERNELS)" == "yes" ]; then \
		ln -f $(SRC_DIR)/linux-kernel*/pkgs/fc*/x86_64/*.rpm $(SRC_DIR)/$(INSTALLER_COMPONENT)/yum/qubes-dom0/rpm/; \
	fi
	@MAKE_TARGET="iso QUBES_RELEASE=$(QUBES_RELEASE)" ./scripts/build $(DIST_DOM0) $(INSTALLER_COMPONENT) root || exit 1
	@ln -f $(SRC_DIR)/$(INSTALLER_COMPONENT)/build/ISO/qubes-x86_64/iso/*.iso iso/ || exit 1
	@echo "The ISO can be found in iso/ subdirectory."
	@echo "Thank you for building Qubes. Have a nice day!"


check:
	@HEADER_PRINTED="" ; for REPO in $(GIT_REPOS); do \
		pushd $$REPO > /dev/null; \
		git status | grep "^nothing to commit" > /dev/null; \
		if [ $$? -ne 0 ]; then \
			if [ X$$HEADER_PRINTED == X ]; then HEADER_PRINTED="1"; echo "Uncommited changes in:"; fi; \
			echo "> $$REPO"; fi; \
	    popd > /dev/null; \
	done; \
	HEADER_PRINTED="" ; for REPO in $(GIT_REPOS); do \
		pushd $$REPO > /dev/null; \
		git tag --points-at HEAD | grep ^. > /dev/null; \
		if [ $$? -ne 0 ]; then \
			if [ X$$HEADER_PRINTED == X ]; then HEADER_PRINTED="1"; echo "Unsigned HEADs in:"; fi; \
			echo "> $$REPO"; fi; \
	    popd > /dev/null; \
	done

diff:
	@for REPO in $(GIT_REPOS); do \
		pushd $$REPO > /dev/null; \
		git status | grep "^nothing to commit" > /dev/null; \
		if [ $$? -ne 0 ]; then \
			(echo -e "Uncommited changes in $$REPO:\n\n"; git diff --color=always) | less -RM +Gg; \
		fi; \
	    popd > /dev/null; \
	done

show:
	@if [ -n "$$REF" ]; then \
		for REPO in $(GIT_REPOS); do \
			pushd $$REPO > /dev/null; \
			git show $(REF) 2>/dev/null && \
			echo $(REF) in $$REPO; \
			popd > /dev/null; \
		done; \
	else \
		echo "Error: show target needs REF= set" >&2; \
	fi

grep-tgt = $(GIT_REPOS:$(SRC_DIR)/%=%.grep)
RE ?= $(filter-out grep $(grep-tgt), $(MAKECMDGOALS))
.PHONY: grep $(grep-tgt)
$(grep-tgt):
	@git -C $(@:%.grep=$(SRC_DIR)/%) grep "$(RE)" | sed "s#^#$(@:%.grep=$(SRC_DIR)\/%)/#"
grep: $(grep-tgt)

switch-branch:
	@for REPO in $(GIT_REPOS); do \
		pushd $$REPO > /dev/null; \
		echo -n "$$REPO: "; \
		BRANCH=$(BRANCH); \
		if [ "$$REPO" == "." ]; then
			branch_var="BRANCH_builder"; \
		else \
			branch_var="BRANCH_`basename $${REPO//-/_}`"; \
		fi; \
		[ -n "$${!branch_var}" ] && BRANCH="$${!branch_var}"; \
		CURRENT_BRANCH=`git branch | sed -n -e 's/^\* \(.*\)/\1/p' | tr -d '\n'`; \
		if [ "$$BRANCH" != "$$CURRENT_BRANCH" ]; then \
			git config --get-color color.decorate.tag "red bold"; \
			echo -n "$$CURRENT_BRANCH -> "; \
			git config --get-color "" "reset"; \
			git checkout "$$BRANCH"; \
		else \
			git config --get-color color.decorate.branch "green bold"; \
			echo "$$CURRENT_BRANCH"; \
		fi; \
		git config --get-color "" "reset"; \
	    popd > /dev/null; \
	done

show-vtags:
	@for REPO in $(GIT_REPOS); do \
		pushd $$REPO > /dev/null; \
		echo -n "$$REPO: "; \
		git config --get-color color.decorate.tag "red bold"; \
		git tag --points-at HEAD | grep "^[Rv]" | tr '\n' ' '; \
		git config --get-color "" "reset"; \
		echo -n '('; \
		BRANCH=$(BRANCH); \
		if [ "$$REPO" == "." ]; then
			branch_var="BRANCH_builder"; \
		else \
			branch_var="BRANCH_`basename $${REPO//-/_}`"; \
		fi; \
		[ -n "$${!branch_var}" ] && BRANCH="$${!branch_var}"; \
		CURRENT_BRANCH=`git branch | sed -n -e 's/^\* \(.*\)/\1/p' | tr -d '\n'`; \
		if [ "$$BRANCH" != "$$CURRENT_BRANCH" ]; then \
			git config --get-color color.decorate.tag "yellow bold"; \
		else \
			git config --get-color color.decorate.branch "green bold"; \
		fi; \
		echo -n $$CURRENT_BRANCH; \
		git config --get-color "" "reset"; \
		echo ')'; \
	    popd > /dev/null; \
	done

show-authors:
	@for REPO in $(GIT_REPOS); do \
		pushd $$REPO > /dev/null; \
		COMPONENT=`basename $$REPO`; \
		[ "$$COMPONENT" == "." ] && COMPONENT=builder; \
		git shortlog -sn | tr -s "\t" ":" | sed "s/^ */$$COMPONENT:/"; \
	    popd > /dev/null; \
	done | awk -F: '{ comps[$$3]=comps[$$3] "\n  " $$1 " (" $$2 ")" } END { for (a in comps) { printf "$(c.bold)" a ":$(c.normal)"; print comps[a]; } }'

push:
	@HEADER_PRINTED="" ; for REPO in $(GIT_REPOS); do \
		pushd $$REPO > /dev/null; \
		BRANCH=$(BRANCH); \
		if [ "$$REPO" == "." ]; then
			branch_var="BRANCH_builder"; \
		else \
			branch_var="BRANCH_`basename $${REPO//-/_}`"; \
		fi; \
		[ -n "$${!branch_var}" ] && BRANCH="$${!branch_var}"; \
		PUSH_REMOTE=`git config branch.$$BRANCH.remote`; \
		[ -n "$(GIT_REMOTE)" ] && PUSH_REMOTE="$(GIT_REMOTE)"; \
		if [ -z "$$PUSH_REMOTE" ]; then \
			echo "No remote repository set for $$REPO, branch $$BRANCH,"; \
			echo "set it with 'git config branch.$$BRANCH.remote <remote-name>'"; \
			echo "Not pushing anything!"; \
		else \
			echo "Pushing changes from $$REPO to remote repo $$PUSH_REMOTE $$BRANCH..."; \
			TAGS_FROM_BRANCH=`git log --oneline --decorate $$BRANCH| grep '^.\{7\} (\(HEAD, \)\?tag: '| sed 's/^.\{7\} (\(HEAD, \)\?\(\(tag: [^, )]*\(, \)\?\)*\).*/\2/;s/tag: //g;s/, / /g'`; \
			[ "$(VERBOSE)" == "0" ] && GIT_OPTS=-q; \
			git push $$GIT_OPTS $$PUSH_REMOTE $$BRANCH $$TAGS_FROM_BRANCH; \
			if [ $$? -ne 0 ]; then exit 1; fi; \
		fi; \
		popd > /dev/null; \
	done; \
	echo "All stuff pushed succesfully."
	
prepare-merge-fetch:
	@set -a; \
	SCRIPT_DIR=$(BUILDER_DIR)/scripts; \
	SRC_ROOT=$(BUILDER_DIR)/$(SRC_DIR); \
	FETCH_ONLY=1; \
	IGNORE_MISSING=1; \
	REPOS="$(GIT_REPOS)"; \
	components_var="REMOTE_COMPONENTS_$${GIT_REMOTE//-/_}"; \
	[ -n "$${!components_var}" ] && REPOS="`echo $${!components_var} | sed 's@^\| @ $(SRC_DIR)/@g'`"; \
	for REPO in $$REPOS; do \
		$$SCRIPT_DIR/get-sources || exit 1; \
	done

prepare-merge: prepare-merge-fetch show-unmerged

show-unmerged:
	@REPOS="$(GIT_REPOS)"; \
	{ echo "Changes to be merged:"; \
	for REPO in $$REPOS; do \
		pushd $$REPO > /dev/null; \
		if [ -n "`git log ..FETCH_HEAD 2>/dev/null`" ]; then \
			if [ -n "`git rev-list FETCH_HEAD..HEAD`" ]; then \
				MERGE_TYPE="`git config --get-color color.decorate.tag 'red bold'`"; \
				MERGE_TYPE="$${MERGE_TYPE}merge"; \
			else \
				MERGE_TYPE="`git config --get-color color.decorate.tag 'green bold'`"; \
				MERGE_TYPE="$${MERGE_TYPE}fast-forward"; \
			fi; \
			MERGE_TYPE="$${MERGE_TYPE}`git config --get-color '' 'reset'`"; \
			echo "> $${REPO#$(SRC_DIR)/} $$MERGE_TYPE: git merge FETCH_HEAD"; \
			git log --topo-order --reverse --pretty=oneline --abbrev-commit --color=always ..FETCH_HEAD; \
		fi; \
		popd > /dev/null; \
	done } | less -RM +Gg

do-merge:
	@REPOS="$(GIT_REPOS)"; \
	components_var="REMOTE_COMPONENTS_$${GIT_REMOTE//-/_}"; \
	[ -n "$${!components_var}" ] && REPOS="`echo $${!components_var} | sed 's@^\| @ $(SRC_DIR)/@g'`"; \
	for REPO in $$REPOS; do \
		git -C $$REPO rev-parse -q --verify FETCH_HEAD >/dev/null || continue; \
		echo "Merging FETCH_HEAD into $$REPO"; \
		git -C $$REPO merge --ff $(GIT_MERGE_OPTS) --no-edit FETCH_HEAD || exit 1; \
	done

do-merge-versions-only:
	@REPOS="$(GIT_REPOS)"; \
	components_var="REMOTE_COMPONENTS_$${GIT_REMOTE//-/_}"; \
	[ -n "$${!components_var}" ] && REPOS="`echo $${!components_var} | sed 's@^\| @ $(SRC_DIR)/@g'`"; \
	for REPO in $$REPOS; do \
		git -C $$REPO rev-parse -q --verify FETCH_HEAD >/dev/null || continue; \
		git -C $$REPO tag --points-at FETCH_HEAD | grep -q '^v' || continue; \
		echo "Merging FETCH_HEAD into $$REPO"; \
		git -C $$REPO merge --ff $(GIT_MERGE_OPTS) --no-edit FETCH_HEAD || exit 1; \
	done

add-remote:
	@if [ "x$${GIT_REMOTE//-/_}" != "x" ]; then \
		for REPO in $(GIT_REPOS); do \
			pushd $$REPO > /dev/null; \
				COMPONENT=$$(basename $$REPO | sed 's/\./builder/g'); \
				git remote add $${GIT_REMOTE//-/_} $(GIT_BASEURL)/$(GIT_PREFIX)$$COMPONENT$(GIT_SUFIX); \
				git fetch $${GIT_REMOTE//-/_}; \
			popd > /dev/null; \
		done; \
	fi; \

# update-repo-* targets only set appropriate variables and call
# internal-update-repo-* targets for the actual work
update-repo-%: MAKE_TARGET=update-repo
update-repo-current: MAKE_TARGET=update-repo-from-snapshot
# unfortunatelly $* here doesn't work as expected (is expanded too late), so
# need to list all of them explicitly
update-repo-current-testing: SNAPSHOT_REPO=current-testing
update-repo-security-testing: SNAPSHOT_REPO=security-testing
update-repo-unstable: SNAPSHOT_REPO=unstable
# exception here: update-repo-current uses snapshot of current-testing
update-repo-current: SNAPSHOT_REPO=current-testing

update-repo-templates-itl-testing: SNAPSHOT_REPO=templates-itl-testing
update-repo-templates-itl: SNAPSHOT_REPO=templates-itl-testing
update-repo-templates-itl: MAKE_TARGET=update-repo-from-snapshot
update-repo-templates-community-testing: SNAPSHOT_REPO=templates-community-testing
update-repo-templates-community: SNAPSHOT_REPO=templates-community-testing
update-repo-templates-community: MAKE_TARGET=update-repo-from-snapshot


# add dependency on each combination of:
# internal-update-repo-$(TARGET_REPO).$(PACKAGE_SET).$(DIST).$(COMPONENT)
# use dots for separating "arguments" to not deal with dashes in component names
ifneq ($(DIST_DOM0),)
update-repo-%: $(addprefix internal-update-repo-%.vm.,$(DISTS_VM_NO_FLAVOR)) $(addprefix internal-update-repo-%.dom0.$(DIST_DOM0).,$(COMPONENTS)) post-update-repo-%
else
update-repo-%: $(addprefix internal-update-repo-%.vm.,$(DISTS_VM_NO_FLAVOR)) post-update-repo-%
endif
	@true

# similar for templates, but set PACKAGE_SET to "dom0" and use full DISTS_VM
# instead of DISTS_VM_NO_FLAVOR
update-repo-templates-%: $(addprefix internal-update-repo-templates-%.vm.,$(DISTS_VM:%=%.linux-template-builder)) post-update-repo-templates-%
	@true


# do not include builder itself in the template (it would fail anyway)
update-repo-template:
	@true

$(addprefix internal-update-repo-current.vm.,$(DISTS_VM_NO_FLAVOR)): internal-update-repo-current.vm.% : $(addprefix internal-update-repo-current.vm.%., $(COMPONENTS_NO_TPL_BUILDER))
	@true
$(addprefix internal-update-repo-current-testing.vm.,$(DISTS_VM_NO_FLAVOR)): internal-update-repo-current-testing.vm.% : $(addprefix internal-update-repo-current-testing.vm.%., $(COMPONENTS_NO_TPL_BUILDER))
	@true
$(addprefix internal-update-repo-security-testing.vm.,$(DISTS_VM_NO_FLAVOR)): internal-update-repo-security-testing.vm.% : $(addprefix internal-update-repo-security-testing.vm.%., $(COMPONENTS_NO_TPL_BUILDER))
	@true
$(addprefix internal-update-repo-unstable.vm.,$(DISTS_VM_NO_FLAVOR)): internal-update-repo-unstable.vm.% : $(addprefix internal-update-repo-unstable.vm.%., $(COMPONENTS_NO_TPL_BUILDER))
	@true

$(addprefix internal-update-repo-templates-%.vm.,$(DISTS_VM_NO_FLAVOR)):
	@true

# setup arguments
internal-update-repo-%: TARGET_REPO = $(word 1, $(subst ., ,$*))
internal-update-repo-%: PACKAGE_SET = $(word 2, $(subst ., ,$*))
internal-update-repo-%: DIST        = $(word 3, $(subst ., ,$*))
internal-update-repo-%: COMPONENT   = $(word 4, $(subst ., ,$*))
internal-update-repo-%: REPO 		= $(SRC_DIR)/$(COMPONENT)
internal-update-repo-%: UPDATE_REPO_SUBDIR = $(TARGET_REPO)/$(PACKAGE_SET)/$(DIST)
# set by scripts/auto-build
internal-update-repo-%: BUILD_LOG_URL = $(word 2,$(subst =, ,$(filter $(COMPONENT)-$(PACKAGE_SET)-$(DIST)=%,$(BUILD_LOGS_URL))))
internal-update-repo-%: $(REPO)

# for templates skip $(PACKAGE_SET)/$(DIST)
internal-update-repo-templates-%: UPDATE_REPO_SUBDIR = $(TARGET_REPO)
# and the actual code
# this is executed for every (DIST,PACKAGE_SET,COMPONENT) combination
internal-update-repo-%:
	@repo_base_var="LINUX_REPO_$(DIST)_BASEDIR"; \
	if [ "$(COMPONENT)" = linux-template-builder ]; then \
		# templates belongs to dom0 repository, even though PACKAGE_SET=vm
		repo_base_var="LINUX_REPO_$(DIST_DOM0)_BASEDIR"; \
	fi; \
	if [ -n "$${!repo_base_var}" ]; then \
		repo_basedir="$${!repo_base_var}"; \
	else \
		repo_basedir="$(LINUX_REPO_BASEDIR)"; \
	fi; \
	if [ -r $(REPO)/Makefile.builder ]; then \
		echo -n "Updating $(REPO)... "; \
		if [ "0$(UPDATE_REPO_CHECK_VTAG)" -eq 1 ]; then \
			vtag=`git -C $(REPO) tag --points-at HEAD --list v*`; \
			if [ -z "$$vtag" ]; then \
				echo "$(c.bold)$(c.red)no version tag$(c.normal)"; \
				exit 0; \
			fi; \
		fi; \
		if [ "$(COMPONENT)" = linux-template-builder ]; then
			export TEMPLATE_NAME=$$(MAKEFLAGS= make -s \
					-C $(SRC_DIR)/linux-template-builder \
					DIST=$(DIST) \
					template-name)
		fi
		component_packages=$$(MAKEFLAGS= $(MAKE) -s -f Makefile.generic \
				DIST=$(DIST) \
				PACKAGE_SET=$(PACKAGE_SET) \
				COMPONENT=`basename $(REPO)` \
				UPDATE_REPO=$(BUILDER_DIR)/$$repo_basedir/$(UPDATE_REPO_SUBDIR) \
				get-var GET_VAR=PACKAGE_LIST); \
		if [ -z "$$component_packages" ]; then \
			echo "no packages."; \
			exit 0; \
		fi; \
		$(MAKE) -s -f Makefile.generic DIST=$(DIST) PACKAGE_SET=$(PACKAGE_SET) \
			COMPONENT=`basename $(REPO)` \
			SNAPSHOT_REPO=$(SNAPSHOT_REPO) \
			TARGET_REPO=$(TARGET_REPO) \
			UPDATE_REPO=$(BUILDER_DIR)/$$repo_basedir/$(UPDATE_REPO_SUBDIR) \
			SNAPSHOT_FILE=$(BUILDER_DIR)/repo-latest-snapshot/$(SNAPSHOT_REPO)-$(PACKAGE_SET)-$(DIST)-`basename $(REPO)` \
			BUILD_LOG_URL=$(BUILD_LOG_URL) \
			$(MAKE_TARGET) || exit 1; \
	elif $(MAKE) -C $(REPO) -n update-repo-$(TARGET_REPO) >/dev/null 2>/dev/null; then \
		echo "Updating $(REPO)... "; \
		DIST=$(DIST) UPDATE_REPO=$(BUILDER_DIR)/$$repo_basedir/$(UPDATE_REPO_SUBDIR) \
		$(MAKE) -s -C $(REPO) update-repo-$(TARGET_REPO) || exit 1; \
	else \
		echo -n "Updating $(REPO)... skipping."; \
	fi; \
	echo

# this is executed only once for all update-repo-* target
post-update-repo-%:
	@for dist in $(DIST_DOM0) $(DISTS_VM_NO_FLAVOR); do \
		repo_base_var="LINUX_REPO_$${dist}_BASEDIR"; \
		if [ -n "$${!repo_base_var}" ]; then \
			repo_basedir="$${!repo_base_var}"; \
		else \
			repo_basedir="$(LINUX_REPO_BASEDIR)"; \
		fi; \
		repos_to_update="$$repos_to_update $$repo_basedir"; \
	done; \
	pkgset_dist= ; \
	for dist in $(DIST_DOM0); do \
		pkgset_dist="$$pkgset_dist dom0/$$dist"; \
	done; \
	for dist in $(DISTS_VM_NO_FLAVOR); do \
		pkgset_dist="$$pkgset_dist vm/$$dist"; \
	done; \
	for repo in `echo $$repos_to_update|tr ' ' '\n'|sort|uniq`; do \
		[ -z "$$repo" ] && continue; \
		[ -x "$$repo/../update_repo-$*.sh" ] || continue; \
		(cd $$repo/.. && ./update_repo-$*.sh r$(RELEASE) $$pkgset_dist); \
	done

template-name:
	@for DIST in $(DISTS_VM); do \
		export DIST; \
		$(MAKE) -s -C $(SRC_DIR)/linux-template-builder template-name; \
	done

check-release-status: $(DISTS_VM_NO_FLAVOR:%=check-release-status-vm-%)

ifneq (,$(DIST_DOM0))
check-release-status: check-release-status-dom0-$(DIST_DOM0) check-release-status-templates
	@true
endif

check-release-status-templates:
	@if [ "0$(HTML_FORMAT)" -eq 1 ]; then \
		printf '<h2>Templates</h2>\n'; \
		printf '<table><tr><th>Template name</th><th>Version</th><th>Status</th></tr>\n'; \
	else \
		echo "-> Checking $(c.bold)templates$(c.normal)"
	fi
	for DIST in $(DISTS_VM); do \
		if ! [ -e $(SRC_DIR)/linux-template-builder/Makefile.builder ]; then \
			# Old style components not supported
			continue; \
		fi; \
		TEMPLATE_NAME=$$(DISTS_VM=$$DIST make -s template-name); \
		if [ "0$(HTML_FORMAT)" -eq 1 ]; then \
			printf '<tr><td>%s</td>' "$$TEMPLATE_NAME"; \
		else \
			echo -n "$$TEMPLATE_NAME: "; \
		fi; \
		$(BUILDER_DIR)/scripts/check-release-status-for-component --color \
			"linux-template-builder" "vm" "$$DIST"; \
		if [ "0$(HTML_FORMAT)" -eq 1 ]; then \
			printf '</tr>\n'; \
		fi; \
	done
	printf '</table>\n'

check-release-status-%: PACKAGE_SET = $(word 1, $(subst -, ,$*))
check-release-status-%: DIST        = $(subst $(null) $(null),-,$(wordlist 2, 10, $(subst -, ,$*)))
check-release-status-%: MAKE_ARGS   = PACKAGE_SET=$(PACKAGE_SET) DIST=$(DIST) COMPONENT=$$C
check-release-status-%:
	@if [ "0$(HTML_FORMAT)" -eq 1 ]; then \
		printf '<h2>Packages for <span class="dist">%s %s</span></h2>\n' "$(DIST)" "$(PACKAGE_SET)"; \
		printf '<table><tr><th>Component</th><th>Version</th><th>Status</th></tr>\n'; \
	else \
		echo "-> Checking packages for $(c.bold)$(DIST) $(PACKAGE_SET)$(c.normal)"; \
	fi
	for C in $(COMPONENTS_NO_TPL_BUILDER); do \
		if ! [ -e $(SRC_DIR)/$$C/Makefile.builder ]; then \
			# Old style components not supported
			continue; \
		fi; \
		if [ -z "`$(MAKE) -s -f Makefile.generic \
				DIST=$(DIST) \
				PACKAGE_SET=$(PACKAGE_SET) \
				COMPONENT=$$C \
				get-var GET_VAR=PACKAGE_LIST 2>/dev/null`" ]; then \
			continue; \
		fi
		if [ "0$(HTML_FORMAT)" -eq 1 ]; then \
			printf '<tr><td>%s</td>' "$$C"; \
		else \
			echo -n "$$C: "; \
		fi; \
		$(BUILDER_DIR)/scripts/check-release-status-for-component --color "$$C" "$(PACKAGE_SET)" "$(DIST)"; \
		if [ "0$(HTML_FORMAT)" -eq 1 ]; then \
			printf '</tr>\n'; \
		fi; \
	done
	printf '</table>\n'

windows-image:
	./win-mksrcimg.sh

windows-image-extract:
	./win-mountsrc.sh mount || exit 1
	( shopt -s nullglob; cd mnt; cp --parents -rft .. qubes-src/*/*.{msi,exe} )
	for REPO in $(GIT_REPOS); do \
		[ $$REPO == '.' ] && break; \
		if [ -r $$REPO/Makefile.builder ]; then \
			$(MAKE) -s -f Makefile.generic DIST=$(DIST_DOM0) PACKAGE_SET=dom0 \
				WINDOWS_IMAGE_DIR=$(BUILDER_DIR)/mnt \
				COMPONENT=`basename $$REPO` \
				windows-image-extract; \
		fi; \
	done; \
	./win-mountsrc.sh umount

.PHONY: build-info
# Only show if VERBOSE != 0 or "build-info" was given on the command line
build-info.show := $(strip $(or $(if $(findstring $(VERBOSE), 0),, y), \
                                $(filter build-info, $(MAKECMDGOALS))))
ifdef build-info.show
build-info:: label  ?= $(c.bold)$(c.blue)
build-info:: text   ?= $(c.normal)
build-info:: _item_added     = $(c.red)$(_ITEM)$(c.normal)
build-info:: _item_unchanged = $(1)$(_ITEM)$(c.normal)
build-info:: _item_removed   = $(c.white)$(_ITEM)$(c.normal)
build-info:: _item = $(strip $(if $(filter $(_ITEM), $(if $(4), $(4), $(_ITEM))), $(_item_unchanged), $(_item_added)))
build-info:: _items = $(strip $(foreach _ITEM, $(3), $(strip $(_item),))) $(_items_removed)
build-info:: _items_removed = $(foreach _ITEM, $(filter-out $(3), $(4)), $(_item_removed))
build-info:: _data = "$(1)$(strip $(_items))" | fmt -w110  | sed -e 's/^/    /'
build-info:: _info = echo -e "$(label)$(strip $(2)):$(c.normal)"; echo -e $(_data)
build-info::
	@echo "================================================================================"
	@echo "                           B U I L D   I N F O                                  "
	@echo -e "Items in $(c.red)red$(c.normal) indicate it was automatically generated by configuration file(s)"
	@echo -e "Items in $(c.white)white$(c.normal) indicate it was automatically removed by configuration file(s)"
	@echo "================================================================================"
	# (1): Item Color, (2): Label, (3): Item, (4): Original item used to compare if changed
	@$(call _info, $(text), DISTS_VM,        $(DISTS_VM), $(_ORIGINAL_DISTS_VM))
	@$(call _info, $(text), DISTS_ALL,       $(DISTS_ALL), $(_ORIGINAL_DISTS_ALL))
	@$(call _info, $(text), DIST_DOM0,       $(DIST_DOM0))
	@$(call _info, $(text), BUILDER_PLUGINS, $(BUILDER_PLUGINS) $(BUILDER_PLUGINS_DISTS), $(_ORIGINAL_BUILDER_PLUGINS))
	@$(call _info, $(text), COMPONENTS,      $(COMPONENTS), $(_ORIGINAL_COMPONENTS))
	@$(call _info, $(text), GIT_REPOS,       $(GIT_REPOS))
	@$(call _info, $(text), TEMPLATE,        $(TEMPLATE), $(_ORIGINAL_TEMPLATE))
	@$(call _info, $(text), TEMPLATE_FLAVOR_DIR,  $(TEMPLATE_FLAVOR_DIR), $(_ORIGINAL_TEMPLATE_FLAVOR_DIR))
	@$(call _info, $(text), TEMPLATE_ALIAS,  $(TEMPLATE_ALIAS), $(_ORIGINAL_TEMPLATE_ALIAS))
	@$(call _info, $(text), TEMPLATE_LABEL,  $(TEMPLATE_LABEL), $(_ORIGINAL_TEMPLATE_LABEL))
	@for component in $(COMPONENTS); do \
		component_env_var=`$(MAKE) -s get-var GET_VAR=ENV_$${component//-/_}`; \
		if [ ! -z "$$component_env_var" ]; then $(call _info, $(text), ENV_$${component//-/_}, $${component_env_var}, ""); fi; \
	done
else
build-info::;
endif

build-id::
	@echo "################################################################################"
	@echo "### The following settings copied to builder.conf will make builder use      ###"
	@echo "### exactly the same sources                                                 ###"
	@echo "################################################################################"
	@for component in $(sort $(COMPONENTS) builder $(BUILDER_PLUGINS_ALL)); do \
		dir="$(SRC_DIR)/$$component"; \
		if [ "$$component" = "builder" ]; then dir="."; fi; \
		if [ -n "`git -C "$$dir" status --porcelain`" ]; then
			echo "*** ERROR: Component $$component not clean - commit or stash the changes!"; \
			exit 1; \
		fi; \
		id=`git -C "$$dir" tag -l --points-at HEAD "v*" | head -n 1`; \
		[ -z "$$id" ] && id=`git -C "$$dir" tag -l --points-at HEAD "R*" | head -n 1`; \
		[ -z "$$id" ] && id=`git -C "$$dir" tag -l --points-at HEAD "*-stable" | head -n 1`; \
		[ -z "$$id" ] && id=`git -C "$$dir" tag -l --points-at HEAD "[0-9]*" | head -n 1`; \
		if [ -z "$$id" ]; then \
			id=`git -C "$$dir" rev-parse HEAD`; \
		fi; \
		echo "BRANCH_$${component//-/_} = $$id"; \
	done

# TODO: Consider changing umount_kill script to the following:
# "fuser -kmM" && umount -R
umount-tgt = $(DISTS_ALL:%=chroot-%.umount) $(SRC_DIR).umount
.PHONY: umount $(umount-tgt)
$(umount-tgt):
	@sudo $(BUILDER_DIR)/scripts/umount_kill.sh $(BUILDER_DIR)/$(@:%.umount=%)
umount: $(umount-tgt)

# Returns variable value
# Example usage: GET_VAR=DISTS_VM make get-var
.PHONY: get-var
get-var::
	@GET_VAR=$${!GET_VAR}; \
	echo "$${GET_VAR}"

.PHONY: install-deps
install-deps: install-deps.$(PKG_MANAGER)

.PHONY: install-deps.rpm
install-deps.rpm::
	@sudo dnf install -y $(DEPENDENCIES) || sudo yum install -y $(DEPENDENCIES)

.PHONY: install-deps.dpkg
install-deps.dpkg::
	@sudo apt-get -y install $(DEPENDENCIES)

.PHONY: about
about::
	@echo "Makefile"

