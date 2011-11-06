
#Include config file
-include builder.conf

DIST_DOM0 ?= fc13
DISTS_VM ?= fc14

SRC_DIR := qubes-src

# Get rid of quotes
DISTS_VM := $(shell echo $(DISTS_VM))

DISTS_ALL := $(filter-out $(DIST_DOM0),$(DISTS_VM)) $(DIST_DOM0)



GIT_REPOS := $(SRC_DIR)/core $(SRC_DIR)/gui \
				$(SRC_DIR)/installer $(SRC_DIR)/kde-dom0 \
				$(SRC_DIR)/kernel $(SRC_DIR)/qubes-manager \
				$(SRC_DIR)/template-builder $(SRC_DIR)/xen \
				$(SRC_DIR)/xfce4-dom0 $(SRC_DIR)/yum \
				.

help:
	@echo "make qubes            -- download and build all components"
	@echo "make get-sources      -- download/update all sources"
	@echo "make xen              -- compile xen packages (for both dom0 and VM)"
	@echo "make core             -- compile qubes-core packages (for both dom0 and VM)"
	@echo "make kernel-xenlinux  -- compile xenlinux kernel package (for dom0)"
	@echo "make kernel-pvops     -- compile pvops kernel package (for VM)"
	@echo "make kernel           -- compile both kernel packages"
	@echo "make gui              -- compile gui packages (for both dom0 and VM)"
	@echo "make template         -- build template of VM system (require above steps to be done first)"
	@echo "make qubes-manager    -- compile xen packages (for dom0)"
	@echo "make kde-dom0         -- compile KDE packages for dom0 UI"
	@echo "make xfce4-dom0       -- compile XFCE4 window manager for dom0 UI (EXPERIMENTAL)"
	@echo "make installer        -- compile installer packages (firstboot and anaconda)"
	@echo "make sign-all         -- sign all packages (useful with NO_SIGN=1 in builder.conf)"
	@echo "make clean-all        -- remove any downloaded sources and builded packages"
	@echo "make clean-rpms       -- remove any downloaded sources and builded packages"
	@echo "make iso              -- update installer repos, make iso"
	@echo "make check            -- check for any uncommited changes and unsiged tags"
	@echo "make push             -- do git push for all repos, including tags"

get-sources:
	./get-all-sources.sh

xen:
	MAKE_TARGET="import-keys rpms" ./build.sh $(DIST_DOM0) xen; \

core:
	for DIST in $(DISTS_ALL); do \
		./build.sh $$DIST core || exit 1; \
	done
	MAKE_TARGET="rpms-vaio-fixes" ./build.sh $(DIST_DOM0) core || exit 1

kernel: kernel-xenlinux kernel-pvops

kernel-xenlinux:
	MAKE_TARGET="BUILD_FLAVOR=xenlinux rpms" ./build.sh $(DIST_DOM0) kernel

kernel-pvops:
	MAKE_TARGET="BUILD_FLAVOR=pvops rpms" ./build.sh $(DIST_DOM0) kernel

gui:
	for DIST in $(DISTS_ALL); do \
		./build.sh $$DIST gui || exit 1; \
	done

qubes-manager:
	./build.sh $(DIST_DOM0) qubes-manager

template:
	for DIST in $(DISTS_VM); do \
		DIST=$$DIST NO_SIGN=$(NO_SIGN) make -C $(SRC_DIR)/template-builder rpms || exit 1; \
	done

kde-dom0:
	MAKE_TARGET="rpms_stage_completed1" ./build.sh $(DIST_DOM0) kde-dom0
	sudo ./prepare-chroot $(PWD)/$(DIST_DOM0) $(DIST_DOM0) build-pkgs-kde-dom0-2.list
	MAKE_TARGET="rpms_stage_completed2" ./build.sh $(DIST_DOM0) kde-dom0
	sudo ./prepare-chroot $(PWD)/$(DIST_DOM0) $(DIST_DOM0) build-pkgs-kde-dom0-3.list
	MAKE_TARGET="rpms_stage_completed3" ./build.sh $(DIST_DOM0) kde-dom0
	sudo ./prepare-chroot $(PWD)/$(DIST_DOM0) $(DIST_DOM0) build-pkgs-kde-dom0-4.list
	MAKE_TARGET="rpms_stage_completed4" ./build.sh $(DIST_DOM0) kde-dom0

installer:
	./build.sh $(DIST_DOM0) installer

xfce4-dom0:
	COMPONENTS="xfce4-dom0" ./get-all-sources.sh
	./build.sh $(DIST_DOM0) xfce4-dom0

sign-all:
	rpm --addsign $(SRC_DIR)/*/rpm/*/*.rpm

qubes: get-sources xen core kernel gui template kde-dom0 installer qubes-manager


clean-installer-rpms:
	rm -rf $(SRC_DIR)/installer/yum/qubes-dom0/rpm/*.rpm
	rm -rf $(SRC_DIR)/installer/yum/installer/rpm/*.rpm
	$(SRC_DIR)/installer/yum/update_repo.sh

clean-rpms: clean-installer-rpms
	rm -rf all-qubes-pkgs/*.rpm

clean-all: clean-rpms
	for dir in $(DISTS_ALL); do sudo umount $$dir/proc; done || true
	sudo rm -rf $(DISTS_ALL)
	rm -rf $(SRC_DIR)

iso:
	make -C $(SRC_DIR)/core update-repo-installer || exit 1
	make -C $(SRC_DIR)/gui update-repo-installer || exit 1
	make -C $(SRC_DIR)/kde-dom0 update-repo-installer || exit 1
	make -C $(SRC_DIR)/kernel BUILD_FLAVOR=pvops update-repo-installer || exit 1
	make -C $(SRC_DIR)/kernel BUILD_FLAVOR=xenlinux update-repo-installer || exit 1
	for DIST in $(DISTS_VM); do \
		DIST=$$DIST make -C $(SRC_DIR)/template-builder update-repo-installer || exit 1; \
	done
	make -C $(SRC_DIR)/qubes-manager update-repo-installer || exit 1
	make -C $(SRC_DIR)/xen update-repo-installer || exit 1
	make -C $(SRC_DIR)/installer update-repo || exit 1
	sudo make -C $(SRC_DIR)/installer/ iso || exit 1



check:
	@HEADER_PRINTED="" ; for REPO in $(GIT_REPOS); do \
		pushd $$REPO > /dev/null; \
		git status | grep -v ^# | grep -v "nothing to commit" > /dev/null;\
		if [ $$? -eq 0 ]; then \
			if [ X$$HEADER_PRINTED == X ]; then HEADER_PRINTED="1"; echo "Uncommited changes in:"; fi ;\
			echo "> $$REPO"; fi; \
	    popd > /dev/null; \
	done;
	@HEADER_PRINTED="" ; for REPO in $(GIT_REPOS); do \
		pushd $$REPO > /dev/null; \
		git tag --contains HEAD | grep ^. > /dev/null;\
		if [ $$? -ne 0 ]; then \
			if [ X$$HEADER_PRINTED == X ]; then HEADER_PRINTED="1"; echo "Unsigned HEADs in:"; fi ;\
			echo "> $$REPO"; fi; \
	    popd > /dev/null; \
	done;\

push:
	@HEADER_PRINTED="" ; for REPO in $(GIT_REPOS); do \
		pushd $$REPO > /dev/null; \
		echo "Pushing changes from $$REPO to remote repo $(GIT_SUBDIR) $(BRANCH)...";\
		git push $(GIT_SUBDIR) $(BRANCH) ;\
		git push $(GIT_SUBDIR) $(BRANCH) --tags ;\
		if [ $$? -ne 0 ]; then exit 1; fi;\
	    popd > /dev/null; \
	done;\
	echo "All stuff pushed succesfully."
	
