# Parent Makefile sets THEOS_PACKAGE_SCHEME (rootless or empty for rootful).
TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = diskprobe-utility

diskprobe-utility_FILES = Sources/main.m
diskprobe-utility_CFLAGS = -fobjc-arc
diskprobe-utility_FRAMEWORKS = Foundation QuartzCore
diskprobe-utility_INSTALL_PATH = /usr/libexec/diskprobe
diskprobe-utility_CODESIGN_FLAGS = -S$(CURDIR)/entitlements.plist

include $(THEOS)/makefiles/tool.mk
