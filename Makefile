# Build version string, taking into account that 'VER_REV' may not be set
VERSION     := $(strip $(shell cat src/Cocoa/oolite-version.xcconfig | cut -d '=' -f 2))
VER_MAJ     := $(shell echo "${VERSION}" | cut -d '.' -f 1)
VER_MIN     := $(shell echo "${VERSION}" | cut -d '.' -f 2)
VER_REV     := $(shell echo "${VERSION}" | cut -d '.' -f 3)
VER_REV     := $(if ${VER_REV},${VER_REV},0)
SVNREVISION := $(shell svn info  | grep Revision | cut -d ' ' -f 2)
VER         := $(shell echo "${VER_MAJ}.${VER_MIN}.${VER_REV}.${SVNREVISION}")
BUILDTIME   := $(shell date "+%Y.%m.%d %H:%M")
DEB_BUILDTIME   := $(shell date "+%a, %d %b %Y %H:%M:%S %z")
ifeq (${VER_REV},0)
DEB_VER     := $(shell echo "${VER_MAJ}.${VER_MIN}")
else
DEB_VER     := $(shell echo "${VER_MAJ}.${VER_MIN}.${VER_REV}")
endif
DEB_REV  := $(shell cat debian/revision)
# Ubuntu versions are: <upstream version>-<deb ver>ubuntu<build ver>
# eg: oolite1.74.4.2755-0ubuntu1
# Oolite versions are: MAJ.min.rev.svn
# eg. 1.74.0.3275
# Our .deb versions are: MAJ.min.rev.svn-<pkg rev>[~<type>]
# eg. 1.74.0.3275-0, 1.74.0.3275-0~test
pkg-debtest: DEB_REV := $(shell echo "0~test${DEB_REV}")
pkg-debsnapshot: DEB_REV := $(shell echo "0~trunk${DEB_REV}")

LIBJS_SRC_DIR=deps/Cross-platform-deps/SpiderMonkey/js/src

ifeq ($(GNUSTEP_HOST_OS),mingw32)
	LIBJS=deps/Windows-x86-deps/DLLs/js32ECMAv5.dll
endif

ifeq ($(GNUSTEP_HOST_OS),linux-gnu)
   # These are the paths for our custom-built Javascript library
   LIBJS_INC_DIR=$(LIBJS_SRC_DIR)
   ifeq ($(JS_OPT),no)
		LIBJS_BIN_DIR=$(LIBJS_SRC_DIR)/Linux_All_DBG.OBJ
		LIBJS_BUILD_FLAGS=
   else
		LIBJS_BIN_DIR=$(LIBJS_SRC_DIR)/Linux_All_OPT.OBJ
		LIBJS_BUILD_FLAGS=BUILD_OPT=1
   endif
	LIBJS=$(LIBJS_BIN_DIR)/libjs.a
endif

DEPS=$(LIBJS)

# define autopackage .apspec file according to the CPU architecture
HOST_ARCH := $(shell echo $(GNUSTEP_HOST_CPU) | sed -e s/i.86/i386/ -e s/amd64/x86_64/ )
ifeq ($(HOST_ARCH),x86_64)
   APSPEC_FILE=installers/autopackage/default.x86_64.apspec
else
   APSPEC_FILE=installers/autopackage/default.x86.apspec
endif

# Here are our default targets
#
.PHONY: debug
debug: $(DEPS)
	make -f GNUmakefile debug=yes

.PHONY: release
release: $(DEPS)
	make -f GNUmakefile debug=no

.PHONY: release-deployment
release-deployment: $(DEPS)
	make -f GNUmakefile DEPLOYMENT_RELEASE_CONFIGURATION=yes debug=no
	
.PHONY: release-snapshot
release-snapshot: $(DEPS)
	make -f GNUmakefile SNAPSHOT_BUILD=yes VERSION_STRING=$(VER) debug=no

# Here are targets using the provided dependencies
.PHONY: deps-debug
deps-debug: $(DEPS)
	make -f GNUmakefile debug=yes use_deps=yes

.PHONY: deps-release
deps-release: $(DEPS)
	make -f GNUmakefile debug=no use_deps=yes
	
.PHONY: deps-release-deployment
deps-release-deployment: $(DEPS)
	make -f GNUmakefile DEPLOYMENT_RELEASE_CONFIGURATION=yes debug=no use_deps=yes
	
.PHONY: deps-release-snapshot
deps-release-snapshot: $(DEPS)
	make -f GNUmakefile SNAPSHOT_BUILD=yes VERSION_STRING=$(VER) debug=no use_deps=yes

$(LIBJS):
ifeq ($(GNUSTEP_HOST_OS),mingw32)
	@echo "ERROR - this Makefile can't (yet) build the Javascript DLL"
	@echo "        Please build it yourself and copy it to $(LIBJS)."
	false
endif
	# When Linux is ready to compile the Javascript engine from source
	# then re-activate the following line of code and update it appropriately
	# make -C $(LIBJS_SRC_DIR) -f Makefile.ref $(LIBJS_BUILD_FLAGS)

.PHONY: clean
clean:
# When Linux is ready to compile the Javascript engine from source
# then re-activate the following block of code and update it appropriately
# ifneq ($(GNUSTEP_HOST_OS),mingw32)
#	make -C $(LIBJS_SRC_DIR)/editline -f Makefile.ref clobber
#	make -C $(LIBJS_SRC_DIR) -f Makefile.ref clobber
#	find $(LIBJS_SRC_DIR) -name "Linux_All_*.OBJ" | xargs rm -Rf
# endif
	make -f GNUmakefile clean
	rm -Rf obj obj.dbg oolite.app

.PHONY: all
all: release release-deployment release-snapshot debug

.PHONY: remake
remake: clean all

.PHONY: deps-all
deps-all: deps-release deps-release-deployment deps-release-snapshot deps-debug

.PHONY: deps-remake
deps-remake: clean deps-all

# Here are our linux autopackager targets
#
pkg-autopackage:
	makepackage -c -m $(APSPEC_FILE)

# Here are our Debian packager targets
#
.PHONY: debian/changelog
debian/changelog:
	cat debian/changelog.in | sed -e "s/@@VERSION@@/${VER}/g" -e "s/@@REVISION@@/${DEB_REV}/g" -e "s/@@TIMESTAMP@@/${DEB_BUILDTIME}/g" > debian/changelog

.PHONY: pkg-deb pkg-debtest pkg-debsnapshot
pkg-deb: debian/changelog
	debuild binary

pkg-debtest: debian/changelog
	debuild binary

pkg-debsnapshot: debian/changelog
	debuild -e SNAPSHOT_BUILD=yes -e VERSION_STRING=$(VER) binary

.PHONY: pkg-debclean
pkg-debclean:
	debuild clean

# And here are our Windows packager targets
#
NSIS="C:\Program Files\NSIS\makensis.exe"
NSISVERSIONS=installers/win32/OoliteVersions.nsh

# Passing arguments cause problems with some versions of NSIS.
# Because of this, we generate them into a separate file and include them.
.PHONY: ${NSISVERSIONS}
${NSISVERSIONS}:
	@echo "; Version Definitions for Oolite" > $@
	@echo "; NOTE - This file is auto-generated by the Makefile, any manual edits will be overwritten" >> $@
	@echo "!define VER_MAJ ${VER_MAJ}" >> $@
	@echo "!define VER_MIN ${VER_MIN}" >> $@
	@echo "!define VER_REV ${VER_REV}" >> $@
	@echo "!define SVNREV ${SVNREVISION}" >> $@
	@echo "!define VERSION ${VER}" >> $@
	@echo "!define BUILDTIME \"${BUILDTIME}\"" >> $@

.PHONY: pkg-win
pkg-win: release ${NSISVERSIONS}
	$(NSIS) installers/win32/OOlite.nsi
	
.PHONY: pkg-win-deployment
pkg-win-deployment: release-deployment ${NSISVERSIONS}
	$(NSIS) installers/win32/OOlite.nsi

.PHONY: pkg-win-snapshot
pkg-win-snapshot: release-snapshot ${NSISVERSIONS}
	@echo "!define SNAPSHOT 1" >> ${NSISVERSIONS}
	$(NSIS) installers/win32/OOlite.nsi

.PHONY: help
help:
	@echo "This is a helper-Makefile to make compiling Oolite easier."
	@echo
	@echo "NOTE (Linux): To build with the dependency libraries provided with Oolite"
	@echo "              source, use 'deps-' prefix with debug, release, release-snapshot"
	@echo "              and release-deployment build options."
	@echo
	@echo "Development Targets:"
	@echo "  debug               - builds a debug executable in oolite.app/oolite.dbg"
	@echo "  release             - builds a release executable in oolite.app/oolite"
	@echo "  release-deployment  - builds a release executable in oolite.app/oolite"
	@echo "  release-snapshot    - builds a snapshot release in oolite.app/oolite"
	@echo "  all                 - builds the above targets"
	@echo "  clean               - removes all generated files"
	@echo
	@echo "Packaging Targets:"
	@echo " Linux:"
	@echo "  pkg-autopackage     - builds a Linux autopackage"
	@echo
	@echo "  pkg-deb             - builds a release Debian package"
	@echo "  pkg-debtest         - builds a test release Debian package"
	@echo "  pkg-debsnapshot     - builds a snapshot release Debian package"
	@echo "  pkg-debclean        - cleans up after a Debian package build"
	@echo
	@echo " Windows Installer:"
	@echo "  pkg-win             - builds a test-release version"
	@echo "  pkg-win-deployment  - builds a release version"
	@echo "  pkg-win-snapshot    - builds a snapshot version"
