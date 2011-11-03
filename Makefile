
#Include config file
-include builder.conf

DIST_DOM0 ?= fc13
DISTS_VM ?= fc14

# Get rid of quotes
DISTS_VM := $(shell echo $(DISTS_VM))

DISTS_ALL := $(filter-out $(DIST_DOM0),$(DISTS_VM)) $(DIST_DOM0)

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
	@echo "make clean            -- remove any downloaded sources and builded packages"

get-sources:
	./get-all-sources.sh

xen:
	MAKE_TARGET="import-keys rpms" ./build.sh $(DIST_DOM0) xen; \

core:
	for DIST in $(DISTS_ALL); do \
		./build.sh $$DIST core || exit 1; \
	done
	MAKE_TARGET="rpms-vaio-fixes" ./build.sh $(DIST_DOM0) core || exit 1; \

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
		TEMPLATE_NAME=$${DIST/fc/fedora-}-x64; \
		NO_SIGN=$(NO_SIGN); \
		export DIST NO_SIGN; \
		cd qubes-src/template-builder && \
		sudo -E ./fedorize_image $$TEMPLATE_NAME.img clean_images/packages.list && \
		./create_symlinks_in_rpms_to_install_dir.sh && \
		sudo -E ./qubeize_image $$TEMPLATE_NAME.img $$TEMPLATE_NAME && \
		./build_template_rpm $$TEMPLATE_NAME || exit 1; \
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
	rpm --addsign qubes-src/*/rpm/*/*.rpm

qubes: get-sources xen core kernel gui template kde-dom0 installer

clean:
	for dir in $(DISTS_ALL); do sudo umount $$dir/proc; done || true
	rm -rf $(DISTS_ALL)
	rm -rf qubes-src
	rm -rf all-qubes-pkgs

	
