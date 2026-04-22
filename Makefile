THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

THEOS_DEVICE_IP ?= 172.20.10.1
THEOS_DEVICE_USER ?= root
THEOS_DEVICE_PASSWORD ?= 1

include $(THEOS)/makefiles/common.mk

SUBPROJECTS = DiskProbeRootless DiskProbeUtilityRootless

include $(THEOS)/makefiles/aggregate.mk
