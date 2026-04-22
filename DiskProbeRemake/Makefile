# Parent Makefile sets THEOS_PACKAGE_SCHEME (rootless or empty for rootful).
TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = DiskProbe

DiskProbe_FILES = \
	Sources/main.m \
	Sources/DPAppDelegate.m \
	Sources/DPApplication.m \
	Sources/DPApplicationUtility.m \
	Sources/DPSplitViewController.m \
	Sources/DPPathViewController.m \
	Sources/DPDirectoryDataSource.m \
	Sources/DPPathInfo.m \
	Sources/DPCatalog.m \
	Sources/DPUserPreferences.m \
	Sources/DPHelper.m \
	Sources/DPAlert.m \
	Sources/DPAlertAction.m \
	Sources/DPBarGraph.m \
	Sources/DPBarSection.m \
	Sources/DPInfoHeader.m \
	Sources/DPNavigationPathView.m \
	Sources/DPPathTableViewCell.m \
	Sources/DPPathCollectionViewCell.m \
	Sources/DPSettingsViewController.m \
	Sources/DPTableViewController.m \
	Sources/DPPopoverAlertViewController.m \
	Sources/DPFilterAlertViewController.m \
	Sources/DPStreamingTask.m \
	Sources/DPOperationQueue.m \
	Sources/DPReachability.m \
	Sources/DPChangelogViewController.m \
	Sources/DPHomeViewController.m \
	Sources/DPStatisticsManager.m \
	Sources/DPPreviewViewController.m \
	Sources/DPContextAction.m \
	Sources/DPContextActionDataSource.m \
	Sources/DPDocument.m \
	Sources/DPUserNotifications.m \
	Sources/DPBackgroundKeepAlive.m \
	Sources/NSData+DPCompression.m \
	Sources/NSFileManager+DP.m \
	Sources/UIColor+DP.m \
	Sources/UIImage+DP.m \
	Sources/UIView+DP.m \
	Sources/UIViewController+DP.m

# ROOTLESS=1 gates /var/jb path prefixes in the source.
DiskProbe_CFLAGS = -fobjc-arc $(if $(THEOS_PACKAGE_SCHEME),-DROOTLESS=1,)
DiskProbe_FRAMEWORKS = UIKit Foundation QuickLook MessageUI SystemConfiguration UserNotifications WebKit AVFoundation AudioToolbox
DiskProbe_PRIVATE_FRAMEWORKS =
DiskProbe_LIBRARIES = z bz2 compression
DiskProbe_INSTALL_PATH = /Applications
DiskProbe_BUNDLE_ID = com.leeksov.DiskProbe

# Entitlements for rootless — allow access to /var/jb and file system
DiskProbe_CODESIGN_FLAGS = -S$(CURDIR)/entitlements.plist

include $(THEOS)/makefiles/application.mk
