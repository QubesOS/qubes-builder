# Set defaults
GIT_SUBDIR ?= mainstream
BRANCH ?= master
GIT_BASEURL ?= git://git.qubes-os.org
GIT_SUFFIX ?= .git
DIST_DOM0 ?= fc18
DISTS_VM ?= fc18
VERBOSE ?= 0
# Beware of build order
COMPONENTS ?= vmm-xen \
			  core-vchan-xen \
			  linux-utils \
			  core-admin \
			  core-admin-linux \
			  core-agent-linux \
			  linux-kernel \
			  gui-common \
			  gui-daemon \
			  gui-agent-linux \
			  gui-agent-xen-hvm-stubdom \
			  qubes-app-linux-split-gpg \
			  qubes-app-linux-tor \
			  qubes-app-thunderbird \
			  qubes-app-linux-pdf-converter \
			  linux-template-builder \
			  desktop-linux-kde \
			  desktop-linux-xfce4 \
			  qubes-manager \
			  linux-dom0-updates \
			  installer-qubes-os \
			  linux-yum \
			  vmm-xen-windows-pvdrivers \
			  antievilmaid

LINUX_REPO_BASEDIR ?= $(SRC_DIR)/linux-yum/current-release
INSTALLER_COMPONENT ?= installer-qubes-os
BACKEND_VMM ?= xen

#Include config file
-include builder.conf

SRC_DIR := qubes-src

# Get rid of quotes
DISTS_VM := $(shell echo $(DISTS_VM))

DISTS_ALL := $(filter-out $(DIST_DOM0),$(DISTS_VM)) $(DIST_DOM0)

GIT_REPOS := $(addprefix $(SRC_DIR)/,$(COMPONENTS)) .

.EXPORT_ALL_VARIABLES:
.ONESHELL:
help:
	@echo "make qubes            -- download and build all components"
	@echo "make get-sources      -- download/update all sources"
	@echo "make sign-all         -- sign all packages"
	@echo "make clean-all        -- remove any downloaded sources and builded packages"
	@echo "make clean-rpms       -- remove any builded packages"
	@echo "make iso              -- update installer repos, make iso"
	@echo "make check            -- check for any uncommited changes and unsiged tags"
	@echo "make push             -- do git push for all repos, including tags"
	@echo "make show-vtags       -- list components version tags (only when HEAD have such) and branches"
	@echo "make prepare-merge    -- fetch the sources from git, but only show new commits instead of merging"
	@echo "make show-unmerged    -- list fetched but unmerged commits (see make prepare-merge)"
	@echo "make do-merge         -- merge fetched commits"
	@echo "make COMPONENT        -- build both dom0 and VM part of COMPONENT"
	@echo "make COMPONENT-dom0   -- build only dom0 part of COMPONENT"
	@echo "make COMPONENT-vm     -- build only VM part of COMPONENT"
	@echo "COMPONENT can be one of:"
	@echo "  $(COMPONENTS)"
	@echo ""
	@echo "You can also specify COMPONENTS=\"c1 c2 c3 ...\" on command line"
	@echo "to operate on subset of components. Example: make COMPONENTS=\"gui\" get-sources"

get-sources:
	@set -a; \
	SCRIPT_DIR=$(CURDIR); \
	SRC_ROOT=$(CURDIR)/$(SRC_DIR); \
	for REPO in $(GIT_REPOS); do \
		$$SCRIPT_DIR/get-sources.sh || exit 1; \
	done

$(filter-out template template-builder kde-dom0 dom0-updates, $(COMPONENTS)): % : %-dom0 %-vm

%-vm:
	@if [ -r $(SRC_DIR)/$*/Makefile.builder ]; then \
		for DIST in $(DISTS_VM); do \
			make --no-print-directory DIST=$$DIST PACKAGE_SET=vm COMPONENT=$* -f Makefile.generic all || exit 1; \
		done; \
	elif [ -n "`make -n -s -C $(SRC_DIR)/$* rpms-vm 2> /dev/null`" ]; then \
	    for DIST in $(DISTS_VM); do \
	        MAKE_TARGET="rpms-vm" ./build.sh $$DIST $* || exit 1; \
	    done; \
	fi

%-dom0:
	@if [ -r $(SRC_DIR)/$*/Makefile.builder ]; then \
		make -f Makefile.generic DIST=$(DIST_DOM0) PACKAGE_SET=dom0 COMPONENT=$* all || exit 1; \
	elif [ -n "`make -n -s -C $(SRC_DIR)/$* rpms-dom0 2> /dev/null`" ]; then \
	    MAKE_TARGET="rpms-dom0" ./build.sh $(DIST_DOM0) $* || exit 1; \
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
template linux-template-builder:
	@for DIST in $(DISTS_VM); do
	    # some sources can be downloaded and verified during template building
	    # process - e.g. archlinux template
	    export GNUPGHOME="$(CURDIR)/keyrings/template-$$DIST"
	    mkdir -p "$$GNUPGHOME"
	    chmod 700 "$$GNUPGHOME"
	    export DIST NO_SIGN
	    make -s -C $(SRC_DIR)/linux-template-builder prepare-repo-template || exit 1
	    for repo in $(GIT_REPOS); do \
	        if [ -r $$repo/Makefile.builder ]; then
				make --no-print-directory -f Makefile.generic \
					PACKAGE_SET=vm \
					COMPONENT=`basename $$repo` \
					UPDATE_REPO=$(CURDIR)/$(SRC_DIR)/linux-template-builder/yum_repo_qubes/$$DIST \
					update-repo || exit 1
	        elif make -C $$repo -n update-repo-template > /dev/null 2> /dev/null; then
	            make -s -C $$repo update-repo-template || exit 1
	        fi
	    done
	    if [ "$(VERBOSE)" -eq 0 ]; then
	        echo "-> Building template $$DIST (logfile: build-logs/template-$$DIST.log)..."
	        make -s -C $(SRC_DIR)/linux-template-builder rpms > build-logs/template-$$DIST.log 2>&1 || exit 1
			echo "--> Done."
	    else
	        make -s -C $(SRC_DIR)/linux-template-builder rpms || exit 1
	    fi
	done

kde-dom0:
	@set -e
	@MAKE_TARGET="rpms_stage_completed1" ./build.sh $(DIST_DOM0) kde-dom0
	@MAKE_TARGET="rpms_stage_completed2" ./build.sh $(DIST_DOM0) kde-dom0
	@MAKE_TARGET="rpms_stage_completed3" ./build.sh $(DIST_DOM0) kde-dom0
	@MAKE_TARGET="rpms_stage_completed4" ./build.sh $(DIST_DOM0) kde-dom0

dom0-updates:
	@set -e
	@MAKE_TARGET="stage0" ./build.sh $(DIST_DOM0) dom0-updates
	@MAKE_TARGET="stage1" ./build.sh $(DIST_DOM0) dom0-updates
	@MAKE_TARGET="stage2" ./build.sh $(DIST_DOM0) dom0-updates
	@MAKE_TARGET="stage3" ./build.sh $(DIST_DOM0) dom0-updates
	@MAKE_TARGET="stage4" ./build.sh $(DIST_DOM0) dom0-updates

# windows build targets
include Makefile.windows

# Sign only unsigend files (naturally we don't expext files with WRONG sigs to be here)
sign-all:
	@echo "-> Signing packages..."
	@if ! [ $(NO_SIGN) ] ; then \
		sudo rpm --import qubes-release-*-signing-key.asc ; \
		echo "--> Checking which packages need to be signed (to avoid double signatures)..." ; \
		FILE_LIST=""; for RPM in $(shell ls $(SRC_DIR)/*/rpm/*/*.rpm) windows-tools/rpm/noarch/*.rpm; do \
			if ! qubes-src/$(INSTALLER_COMPONENT)/rpm_verify $$RPM > /dev/null; then \
				FILE_LIST="$$FILE_LIST $$RPM" ;\
			fi ;\
		done ; \
		echo "--> Singing..."; \
		RPMSIGN_OPTS=; \
		if [ -n "$$SIGN_KEY" ]; then \
			RPMSIGN_OPTS="--define=%_gpg_name $$SIGN_KEY"; \
			echo "RPMSIGN_OPTS = $$RPMSIGN_OPTS"; \
		fi; \
		sudo chmod go-rw /dev/tty ;\
		echo | rpmsign "$$RPMSIGN_OPTS" --addsign $$FILE_LIST ;\
		sudo chmod go+rw /dev/tty ;\
	else \
		echo  "--> NO_SIGN given, skipping package signing!" ;\
	fi; \
	for dist in $(shell ls qubes-rpms-mirror-repo/); do \
		if [ -d qubes-rpms-mirror-repo/$$dist/rpm ]; then \
			sudo ./update-local-repo.sh $$dist; \
		fi \
	done

qubes: get-sources $(COMPONENTS) sign-all

clean-installer-rpms:
	(cd qubes-src/$(INSTALLER_COMPONENT)/yum || cd qubes-src/$(INSTALLER_COMPONENT)/yum && ./clean_repos.sh)

clean-rpms: clean-installer-rpms
	@for dist in $(shell ls qubes-rpms-mirror-repo/); do \
		echo "Cleaning up rpms in qubes-rpms-mirror-repo/$$dist/rpm/..."; \
		sudo rm -rf qubes-rpms-mirror-repo/$$dist/rpm/*.rpm || true ;\
		createrepo -q --update qubes-rpms-mirror-repo || true; \
	done
	@echo 'Cleaning up rpms in qubes-src/*/rpm/*/*...'; \
	sudo rm -fr qubes-src/*/rpm/*/*.rpm || true; \


clean:
	@for REPO in $(GIT_REPOS); do \
		echo "$$REPO" ;\
		if ! [ -d $$REPO ]; then \
			continue; \
		elif [ $$REPO == "$(SRC_DIR)/template-builder" ]; then \
			for DIST in $(DISTS_VM); do \
				DIST=$$DIST make -s -C $$REPO clean || exit 1; \
			done ;\
		elif [ $$REPO == "$(SRC_DIR)/yum" ]; then \
			echo ;\
		elif [ $$REPO == "." ]; then \
			echo ;\
		else \
			make -s -C $$REPO clean; \
		fi ;\
	done;

clean-all: clean-rpms clean
	for dir in $(DISTS_ALL); do \
		if ! [ -d chroot-$$dir ]; then continue; fi; \
		sudo umount chroot-$$dir/proc; \
		sudo umount chroot-$$dir/tmp/qubes-rpms-mirror-repo; \
	done || true
	sudo rm -rf $(addprefix chroot-,$(DISTS_ALL)) || true
	sudo rm -rf $(SRC_DIR) || true

.PHONY: iso
iso:
	@echo "-> Preparing for ISO build..."
	@make -s -C $(SRC_DIR)/$(INSTALLER_COMPONENT) clean-repos || exit 1
	@echo "--> Copying RPMs from individual repos..."
	@for repo in $(filter-out linux-template-builder,$(GIT_REPOS)); do \
	    if [ -r $$repo/Makefile.builder ]; then
			make --no-print-directory -f Makefile.generic \
				PACKAGE_SET=dom0 \
				DIST=$(DIST_DOM0) \
				COMPONENT=`basename $$repo` \
				UPDATE_REPO=$(CURDIR)/$(SRC_DIR)/$(INSTALLER_COMPONENT)/yum/qubes-dom0 \
				update-repo || exit 1
	    elif make -s -C $$repo -n update-repo-installer > /dev/null 2> /dev/null; then \
	        if ! make -s -C $$repo update-repo-installer ; then \
				echo "make update-repo-installer failed for repo $$repo"; \
				exit 1; \
			fi \
	    fi; \
	done
	@for DIST in $(DISTS_VM); do \
		if ! DIST=$$DIST UPDATE_REPO=$(CURDIR)/$(SRC_DIR)/$(INSTALLER_COMPONENT)/yum/qubes-dom0 \
			make -s -C $(SRC_DIR)/linux-template-builder update-repo-installer ; then \
				echo "make update-repo-installer failed for template dist=$$DIST"; \
				exit 1; \
		fi \
	done
	@make -s -C $(SRC_DIR)/$(INSTALLER_COMPONENT) update-repo || exit 1
	@MAKE_TARGET="iso QUBES_RELEASE=$(QUBES_RELEASE)" ./build.sh $(DIST_DOM0) $(INSTALLER_COMPONENT) root || exit 1
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
		git tag --contains HEAD | grep ^. > /dev/null; \
		if [ $$? -ne 0 ]; then \
			if [ X$$HEADER_PRINTED == X ]; then HEADER_PRINTED="1"; echo "Unsigned HEADs in:"; fi; \
			echo "> $$REPO"; fi; \
	    popd > /dev/null; \
	done

show-vtags:
	@for REPO in $(GIT_REPOS); do \
		pushd $$REPO > /dev/null; \
		echo -n "$$REPO: "; \
		git config --get-color color.decorate.tag "red bold"; \
		git tag --contains HEAD | grep "^[Rv]" | tr '\n' ' '; \
		git config --get-color "" "reset"; \
		echo -n '('; \
		git config --get-color color.decorate.branch "green bold"; \
		git branch | sed -n -e 's/^\* \(.*\)/\1/p' | tr -d '\n'; \
		git config --get-color "" "reset"; \
		echo ')'; \
	    popd > /dev/null; \
	done

push:
	@HEADER_PRINTED="" ; for REPO in $(GIT_REPOS); do \
		pushd $$REPO > /dev/null; \
		PUSH_REMOTE=`git config branch.$(BRANCH).remote`; \
		[ -n "$(GIT_REMOTE)" ] && PUSH_REMOTE="$(GIT_REMOTE)"; \
		if [ -z "$$PUSH_REMOTE" ]; then \
			echo "No remote repository set for $$REPO, branch $(BRANCH),"; \
			echo "set it with 'git config branch.$(BRANCH).remote <remote-name>'"; \
			echo "Not pushing anything!"; \
		else \
			echo "Pushing changes from $$REPO to remote repo $$PUSH_REMOTE $(BRANCH)..."; \
			TAGS_FROM_BRANCH=`git log --oneline --decorate $(BRANCH)| grep '^.\{7\} (\(HEAD, \)\?tag: '| sed 's/^.\{7\} (\(HEAD, \)\?\(\(tag: [^, )]*\(, \)\?\)*\).*/\2/;s/tag: //g;s/, / /g'`; \
			[ "$(VERBOSE)" == "0" ] && GIT_OPTS=-q; \
			git push $$GIT_OPTS $$PUSH_REMOTE $(BRANCH) $$TAGS_FROM_BRANCH; \
			if [ $$? -ne 0 ]; then exit 1; fi; \
		fi; \
		popd > /dev/null; \
	done; \
	echo "All stuff pushed succesfully."
	
# Force bash for some advanced substitution (eg ${!...})
SHELL = /bin/bash
prepare-merge:
	@set -a; \
	SCRIPT_DIR=$(CURDIR); \
	SRC_ROOT=$(CURDIR)/$(SRC_DIR); \
	FETCH_ONLY=1; \
	REPOS="$(GIT_REPOS)"; \
	components_var="REMOTE_COMPONENTS_$${GIT_REMOTE//-/_}"; \
	[ -n "$${!components_var}" ] && REPOS="`echo $${!components_var} | sed 's@^\| @ $(SRC_DIR)/@g'`"; \
	for REPO in $$REPOS; do \
		$$SCRIPT_DIR/get-sources.sh || exit 1; \
	done; \
	$(MAKE) --no-print-directory show-unmerged

show-unmerged:
	@set -a; \
	REPOS="$(GIT_REPOS)"; \
	echo "Changes to be merged:"; \
	for REPO in $$REPOS; do \
		pushd $$REPO > /dev/null; \
		if [ -n "`git log ..FETCH_HEAD`" ]; then \
			if [ -n "`git rev-list FETCH_HEAD..HEAD`" ]; then \
				MERGE_TYPE="`git config --get-color color.decorate.tag 'red bold'`"; \
				MERGE_TYPE="$${MERGE_TYPE}merge"; \
			else; \
				MERGE_TYPE="`git config --get-color color.decorate.tag 'green bold'`"; \
				MERGE_TYPE="$${MERGE_TYPE}fast-forward"; \
			fi; \
			MERGE_TYPE="$${MERGE_TYPE}`git config --get-color '' 'reset'`"; \
			echo "> $$REPO $$MERGE_TYPE: git merge FETCH_HEAD"; \
			git log --pretty=oneline --abbrev-commit ..FETCH_HEAD; \
		fi; \
		popd > /dev/null; \
	done

do-merge:
	@set -a; \
	REPOS="$(GIT_REPOS)"; \
	for REPO in $$REPOS; do \
		pushd $$REPO > /dev/null; \
		echo "Merging FETCH_HEAD into $$REPO"; \
		git merge --no-edit FETCH_HEAD || exit 1; \
		popd > /dev/null; \
	done

update-repo-current update-repo-current-testing update-repo-unstable: update-repo-%:
	@for REPO in $(GIT_REPOS); do \
		[ $$REPO == '.' ] && break; \
		if [ -r $$REPO/Makefile.builder ]; then \
			echo "Updating $$REPO..."; \
			make -s -f Makefile.generic DIST=$(DIST_DOM0) PACKAGE_SET=dom0 \
				UPDATE_REPO=$(CURDIR)/$(LINUX_REPO_BASEDIR)/$*/dom0 \
				COMPONENT=`basename $$REPO` \
				update-repo; \
			for DIST in $(DISTS_VM); do \
				make -s -f Makefile.generic DIST=$$DIST PACKAGE_SET=vm \
					UPDATE_REPO=$(CURDIR)/$(LINUX_REPO_BASEDIR)/$*/vm/$$DIST \
					COMPONENT=`basename $$REPO` \
					update-repo; \
			done; \
		elif make -C $$REPO -n update-repo-$* >/dev/null 2>/dev/null; then \
			echo "Updating $$REPO... "; \
			make -s -C $$REPO update-repo-$* || echo; \
		else \
			echo "Updating $$REPO... skipping."; \
		fi; \
	done; \
	(cd $(LINUX_REPO_BASEDIR)/.. && ./update_repo-$*.sh)
