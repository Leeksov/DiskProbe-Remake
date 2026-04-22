# Build scheme: `rootless` (default, installs under /var/jb) or `rootful`
# (installs under /). Override on the make command line, e.g.:
#   make package SCHEME=rootful
SCHEME ?= rootless
ifeq ($(SCHEME),rootful)
THEOS_PACKAGE_SCHEME =
else
THEOS_PACKAGE_SCHEME = rootless
endif

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

# Per-scheme package filename suffix so rootful and rootless .debs don't clash.
THEOS_PACKAGE_FILENAME = $(THEOS_PACKAGE_BASE_NAME)_$(THEOS_PACKAGE_INSTALLED_VERSION)-$(SCHEME)_$(THEOS_CURRENT_ARCHITECTURE).deb

THEOS_DEVICE_IP ?= 172.20.10.1
THEOS_DEVICE_USER ?= root
THEOS_DEVICE_PASSWORD ?= 1

include $(THEOS)/makefiles/common.mk

SUBPROJECTS = DiskProbeRemake DiskProbeUtilityRemake

include $(THEOS)/makefiles/aggregate.mk
