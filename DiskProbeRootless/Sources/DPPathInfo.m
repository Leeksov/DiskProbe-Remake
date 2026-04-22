#import "DPPathInfo.h"
#import "DPHelper.h"
#import "DPCatalog.h"
#import "DPApplicationUtility.h"
#import "DPPreviewViewController.h"
#import <stdlib.h>
#import <limits.h>

// NSTask is SPI on iOS; declare the minimal selectors we use.
@interface NSTask : NSObject
- (instancetype)init;
@property (copy) NSString *launchPath;
@property (copy) NSArray<NSString *> *arguments;
- (void)launch;
- (void)waitUntilExit;
@property (readonly) int terminationStatus;
@end

// Helper used only by -urlInfo to build a localized row dictionary.
static inline NSString *DPLocalized(NSString *key) {
    return [[NSBundle mainBundle] localizedStringForKey:key value:@"" table:nil];
}

static inline NSDictionary *DPRow(NSString *title, NSString *subtitle, NSString *cellStyle) {
    return @{
        @"title": title ?: @"???",
        @"subtitle": subtitle ?: @"???",
        @"cellStyle": cellStyle ?: @"subtitle",
    };
}

static inline NSDictionary *DPSection(NSString *header, NSArray *rows) {
    return @{
        @"header": @{@"title": header ?: @""},
        @"rows": rows ?: @[],
    };
}

@implementation DPPathInfo

+ (instancetype)pathInfoWithURL:(NSURL *)url {
    return [self pathInfoWithURL:url bytes:0 modification:nil symbolic:NO hidden:NO];
}

+ (instancetype)pathInfoWithURL:(NSURL *)url
                          bytes:(unsigned long long)bytes
                   modification:(NSDate *)modification
                       symbolic:(BOOL)symbolic
                         hidden:(BOOL)hidden {
    DPPathInfo *info = [[DPPathInfo alloc] init];
    info.path = url;
    info.name = url.lastPathComponent;
    info.bytes = bytes;
    info.modificationDate = modification;
    info.isSymbolicLink = symbolic;
    info.isHidden = hidden;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSDictionary *attrs = [fm attributesOfItemAtPath:url.path error:&err];
    if (!err) {
        info.isDirectory = [attrs[NSFileType] isEqualToString:NSFileTypeDirectory];
        if (bytes == 0) info.bytes = [attrs[NSFileSize] unsignedLongLongValue];
        if (!modification) info.modificationDate = attrs[NSFileModificationDate];
    }

    // Resolve symbolic link target (if any) using realpath(3). This follows the
    // whole chain and returns an absolute canonical path. If resolution fails
    // (dangling link, permission error, etc.) we leave symbolicPath = nil.
    if (symbolic && url.path.length) {
        char resolved[PATH_MAX] = {0};
        if (realpath(url.path.fileSystemRepresentation, resolved) != NULL) {
            NSString *targetStr = [fm stringWithFileSystemRepresentation:resolved length:strlen(resolved)];
            if (targetStr.length) {
                info.symbolicPath = [NSURL fileURLWithPath:targetStr];
                // Resolve the target's attributes so navigation/sorting work.
                NSDictionary *targetAttrs = [fm attributesOfItemAtPath:targetStr error:NULL];
                if (targetAttrs) {
                    // If target is a directory, flag as directory so navigation
                    // pushes a new PathVC (but keep isSymbolicLink = YES so the
                    // UI still shows the link indicator).
                    if ([targetAttrs[NSFileType] isEqualToString:NSFileTypeDirectory]) {
                        info.isDirectory = YES;
                    }
                    // Use the target's bytes (not the tiny inode size) for
                    // sizeLabel / sorting.
                    unsigned long long targetBytes = [targetAttrs[NSFileSize] unsignedLongLongValue];
                    if (targetBytes > 0) info.bytes = targetBytes;
                }
            }
        }
    }

    // Detect .app bundle
    if ([url.path hasSuffix:@".app"] && info.isDirectory) {
        info.isApplication = YES;
        NSString *infoPath = [url.path stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        info.applicationName = plist[@"CFBundleDisplayName"] ?: plist[@"CFBundleName"] ?: info.name;
        info.applicationBundle = plist;
    }

    // Detect image
    NSArray *imgExts = @[@"jpg", @"jpeg", @"png", @"gif", @"heic", @"tiff", @"bmp", @"webp"];
    if ([imgExts containsObject:url.pathExtension.lowercaseString]) {
        info.isImage = YES;
    }

    // Detect hidden (dot-prefixed)
    if ([info.name hasPrefix:@"."]) info.isHidden = YES;

    return info;
}

- (NSString *)displayName {
    if (self.isApplication && self.applicationName.length)
        return self.applicationName;
    return self.name;
}

- (NSString *)sizeLabel {
    unsigned long long sz = self.bytes;
    if (self.isDirectory) {
        // For symlinks, use the resolved target path so the catalog looks up
        // the target's size — not the tiny inode size of the link itself.
        NSString *p = nil;
        if (self.isSymbolicLink && self.symbolicPath) {
            p = self.symbolicPath.path;
        }
        if (!p.length) p = self.path.path;
        sz = [[DPCatalog sharedCatalog] sizeForPath:p];
        if (sz == 0) {
            [[DPCatalog sharedCatalog] computeSizeForPathAsync:p];
            return @"—";
        }
    }
    return [DPHelper formatFileSize:sz];
}

- (UIImage *)displayImageWithSource:(DPPathInfoImageSource)source {
    if (source == DPPathInfoImageSourceApp && self.isApplication) {
        NSString *iconPath = [self.path.path stringByAppendingPathComponent:@"AppIcon60x60@2x.png"];
        UIImage *icon = [UIImage imageWithContentsOfFile:iconPath];
        if (icon) return icon;
    }
    if (source == DPPathInfoImageSourceFile && self.isImage) {
        return [UIImage imageWithContentsOfFile:self.path.path];
    }
    // SF Symbol fallback
    if (self.isDirectory) return [UIImage systemImageNamed:@"folder.fill"];
    if (self.isApplication) return [UIImage systemImageNamed:@"app.fill"];
    if (self.isSymbolicLink) return [UIImage systemImageNamed:@"link"];
    return [UIImage systemImageNamed:@"doc.fill"];
}

- (NSDictionary *)directoryInfo {
    if (!self.isDirectory) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSDictionary *attrs = [fm attributesOfItemAtPath:self.path.path error:&err];
    unsigned long long size = [[DPCatalog sharedCatalog] sizeForPath:self.path.path];
    return @{
        @"path": self.path.path,
        @"name": self.displayName,
        @"size": @(size),
        @"sizeLabel": [DPHelper formatFileSize:size],
        @"permissions": [DPHelper permissionsStringForAttributes:attrs] ?: @"—",
        @"modified": attrs[NSFileModificationDate] ?: [NSNull null],
        @"owner": attrs[NSFileOwnerAccountName] ?: @"—",
        @"group": attrs[NSFileGroupOwnerAccountName] ?: @"—",
    };
}

- (NSDictionary *)applicationInfo {
    if (!self.isApplication) return nil;
    return @{
        @"path": self.path.path,
        @"name": self.displayName,
        @"bundleID": self.applicationBundle[@"CFBundleIdentifier"] ?: @"—",
        @"version": self.applicationBundle[@"CFBundleShortVersionString"] ?: @"—",
        @"build": self.applicationBundle[@"CFBundleVersion"] ?: @"—",
    };
}

- (NSDictionary *)urlInfo {
    // Resource values fetched once for the whole method.
    static NSArray<NSURLResourceKey> *sKeys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sKeys = @[
            NSURLNameKey, NSURLLocalizedNameKey, NSURLPathKey, NSURLCanonicalPathKey,
            NSURLParentDirectoryURLKey, NSURLVolumeURLKey,
            NSURLIsReadableKey, NSURLIsWritableKey, NSURLIsExecutableKey,
            NSURLCreationDateKey, NSURLContentModificationDateKey, NSURLContentAccessDateKey,
            NSURLAttributeModificationDateKey, NSURLAddedToDirectoryDateKey,
            NSURLFileSizeKey, NSURLTypeIdentifierKey, NSURLLocalizedTypeDescriptionKey,
            NSURLPreferredIOBlockSizeKey,
            NSURLIsRegularFileKey, NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey,
            NSURLIsHiddenKey, NSURLHasHiddenExtensionKey,
            NSURLIsVolumeKey, NSURLIsApplicationKey,
            NSURLIsSystemImmutableKey, NSURLIsUserImmutableKey, NSURLIsMountTriggerKey,
            NSURLLinkCountKey, NSURLIsExcludedFromBackupKey, NSURLDocumentIdentifierKey,
        ];
    });

    NSDictionary *res = [self.path resourceValuesForKeys:sKeys error:nil] ?: @{};

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:self.path.path error:nil] ?: @{};

    NSMutableArray *sections = [NSMutableArray array];

    // -------- Application Info (optional) --------
    if (self.isApplication && [self.applicationBundle respondsToSelector:@selector(length)] && [(NSString *)self.applicationBundle length]) {
        NSDictionary *appInfo = [DPApplicationUtility applicationInfoForBundleIdentifier:(NSString *)self.applicationBundle] ?: @{};
        NSArray *rows = @[
            DPRow(DPLocalized(@"Bundle Version"),       appInfo[@"VERSION"],        @"value1"),
            DPRow(DPLocalized(@"Bundle Short Version"), appInfo[@"SHORT_VERSION"],  @"value1"),
            DPRow(DPLocalized(@"Application Name"),     appInfo[@"NAME"],           @"subtitle"),
            DPRow(DPLocalized(@"Application Short Name"), appInfo[@"DISPLAY_NAME"], @"subtitle"),
            DPRow(DPLocalized(@"Bundle Identifier"),    appInfo[@"APP_ID"],         @"subtitle"),
            DPRow(DPLocalized(@"Bundle Path"),          appInfo[@"BUNDLE_PATH"],    @"subtitle"),
            DPRow(DPLocalized(@"Application Path"),     appInfo[@"APP_PATH"],       @"subtitle"),
            DPRow(DPLocalized(@"Data Path"),            appInfo[@"DATA_PATH"],      @"subtitle"),
            DPRow(DPLocalized(@"Container Path"),       appInfo[@"CONTAINER_PATH"], @"subtitle"),
            DPRow(DPLocalized(@"Home Path"),            appInfo[@"HOME_PATH"],      @"subtitle"),
            DPRow(DPLocalized(@"Environment Variables"), appInfo[@"ENVIRONMENT"],   @"subtitle"),
        ];
        [sections addObject:DPSection(DPLocalized(@"Application Info"), rows)];
    }

    // -------- Path Info --------
    {
        NSString *symPath = self.symbolicPath.path;
        NSArray *rows = @[
            DPRow(DPLocalized(@"Display Name"),
                  self.displayName, @"subtitle"),
            DPRow(DPLocalized(@"Name"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLNameKey inValue:res[NSURLNameKey]], @"subtitle"),
            DPRow(DPLocalized(@"Localized Name"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLLocalizedNameKey inValue:res[NSURLLocalizedNameKey]], @"subtitle"),
            DPRow(DPLocalized(@"Path"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLPathKey inValue:res[NSURLPathKey]], @"subtitle"),
            DPRow(DPLocalized(@"Absolute Path"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLCanonicalPathKey inValue:res[NSURLCanonicalPathKey]], @"subtitle"),
            DPRow(DPLocalized(@"Symbolic Path"),
                  symPath, @"subtitle"),
            DPRow(DPLocalized(@"Parent Path"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLParentDirectoryURLKey inValue:res[NSURLParentDirectoryURLKey]], @"subtitle"),
            DPRow(DPLocalized(@"Parent Volume"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLVolumeURLKey inValue:res[NSURLVolumeURLKey]], @"subtitle"),
        ];
        [sections addObject:DPSection(DPLocalized(@"Path Info"), rows)];
    }

    // -------- Permissions --------
    {
        NSString *posixLabel = self.permissionsLabel ?: [DPHelper permissionsStringForAttributes:attrs];
        NSArray *rows = @[
            DPRow(DPLocalized(@"Owner Name"),
                  [attrs fileOwnerAccountName], @"value1"),
            DPRow(DPLocalized(@"Group Name"),
                  [attrs fileGroupOwnerAccountName], @"value1"),
            DPRow(DPLocalized(@"Owner ID"),
                  [NSString stringWithFormat:@"%lu", (unsigned long)[[attrs fileOwnerAccountID] unsignedLongValue]], @"value1"),
            DPRow(DPLocalized(@"Group ID"),
                  [NSString stringWithFormat:@"%lu", (unsigned long)[[attrs fileGroupOwnerAccountID] unsignedLongValue]], @"value1"),
            DPRow(DPLocalized(@"Posix"),
                  [NSString stringWithFormat:@"%tu", (NSUInteger)[attrs filePosixPermissions]], @"value1"),
            DPRow(DPLocalized(@"Posix Display"),
                  posixLabel, @"value1"),
            DPRow(DPLocalized(@"Readable"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsReadableKey inValue:res[NSURLIsReadableKey]], @"value1"),
            DPRow(DPLocalized(@"Writable"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsWritableKey inValue:res[NSURLIsWritableKey]], @"value1"),
            DPRow(DPLocalized(@"Executable"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsExecutableKey inValue:res[NSURLIsExecutableKey]], @"value1"),
        ];
        [sections addObject:DPSection(DPLocalized(@"Permissions"), rows)];
    }

    // -------- Dates --------
    {
        NSArray *rows = @[
            DPRow(DPLocalized(@"Creation Date"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLCreationDateKey inValue:res[NSURLCreationDateKey]], @"subtitle"),
            DPRow(DPLocalized(@"Modification Date"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLContentModificationDateKey inValue:res[NSURLContentModificationDateKey]], @"subtitle"),
            DPRow(DPLocalized(@"Access Date"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLContentAccessDateKey inValue:res[NSURLContentAccessDateKey]], @"subtitle"),
            DPRow(DPLocalized(@"FS Modification Date"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLAttributeModificationDateKey inValue:res[NSURLAttributeModificationDateKey]], @"subtitle"),
            DPRow(DPLocalized(@"Added To Directory Date"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLAddedToDirectoryDateKey inValue:res[NSURLAddedToDirectoryDateKey]], @"subtitle"),
        ];
        [sections addObject:DPSection(DPLocalized(@"Dates"), rows)];
    }

    // -------- File Info --------
    {
        NSNumber *sizeNum = res[NSURLFileSizeKey];
        NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:[sizeNum longLongValue]
                                                           countStyle:NSByteCountFormatterCountStyleFile];
        NSArray *rows = @[
            DPRow(DPLocalized(@"Type"),
                  [attrs fileType], @"value1"),
            DPRow(DPLocalized(@"File Size"),
                  sizeStr, @"value1"),
            DPRow(DPLocalized(@"Display Size"),
                  [self sizeLabel], @"value1"),
            DPRow(DPLocalized(@"MIME"),
                  [DPHelper mimeTypeForFile:self.path.path], @"subtitle"),
            DPRow(DPLocalized(@"UTI"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLTypeIdentifierKey inValue:res[NSURLTypeIdentifierKey]], @"subtitle"),
            DPRow(DPLocalized(@"Localized UTI"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLLocalizedTypeDescriptionKey inValue:res[NSURLLocalizedTypeDescriptionKey]], @"subtitle"),
            DPRow(DPLocalized(@"Block Size"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLPreferredIOBlockSizeKey inValue:res[NSURLPreferredIOBlockSizeKey]], @"value1"),
            DPRow(DPLocalized(@"Regular File"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsRegularFileKey inValue:res[NSURLIsRegularFileKey]], @"value1"),
            DPRow(DPLocalized(@"Directory"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsDirectoryKey inValue:res[NSURLIsDirectoryKey]], @"value1"),
            DPRow(DPLocalized(@"Symbolic Link"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsSymbolicLinkKey inValue:res[NSURLIsSymbolicLinkKey]], @"value1"),
            DPRow(DPLocalized(@"Hidden"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsHiddenKey inValue:res[NSURLIsHiddenKey]], @"value1"),
            DPRow(DPLocalized(@"Hidden Extension"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLHasHiddenExtensionKey inValue:res[NSURLHasHiddenExtensionKey]], @"value1"),
            DPRow(DPLocalized(@"Volume Root"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsVolumeKey inValue:res[NSURLIsVolumeKey]], @"value1"),
            DPRow(DPLocalized(@"Application Root"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsApplicationKey inValue:res[NSURLIsApplicationKey]], @"value1"),
            DPRow(DPLocalized(@"System Immutable"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsSystemImmutableKey inValue:res[NSURLIsSystemImmutableKey]], @"value1"),
            DPRow(DPLocalized(@"User Immutable"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsUserImmutableKey inValue:res[NSURLIsUserImmutableKey]], @"value1"),
            DPRow(DPLocalized(@"User Immutable"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsMountTriggerKey inValue:res[NSURLIsMountTriggerKey]], @"value1"),
            DPRow(DPLocalized(@"Hard Link Count"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLLinkCountKey inValue:res[NSURLLinkCountKey]], @"value1"),
            DPRow(DPLocalized(@"Backup Excluded"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsExcludedFromBackupKey inValue:res[NSURLIsExcludedFromBackupKey]], @"value1"),
            DPRow(DPLocalized(@"Document ID"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLDocumentIdentifierKey inValue:res[NSURLDocumentIdentifierKey]], @"value1"),
        ];
        [sections addObject:DPSection(DPLocalized(@"File Info"), rows)];
    }

    return @{
        @"title": @"Info",
        @"sections": sections,
    };
}

- (BOOL)isApplicationInstalled {
    if (!self.isApplication) return NO;
    NSString *bundleID = self.applicationBundle[@"CFBundleIdentifier"];
    if (!bundleID) return NO;
    // Check via LSApplicationWorkspace if available
    Class lsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (lsClass) {
        id workspace = [lsClass performSelector:@selector(defaultWorkspace)];
        NSArray *apps = [workspace performSelector:@selector(allInstalledApplications)];
        for (id app in apps) {
            if ([[app performSelector:@selector(applicationIdentifier)] isEqualToString:bundleID])
                return YES;
        }
    }
    return NO;
}

- (BOOL)removeItem {
    NSError *err = nil;
    return [[NSFileManager defaultManager] removeItemAtURL:self.path error:&err];
}

- (BOOL)uninstallItem {
    // Attempt dpkg removal if available
    NSString *bundleID = self.applicationBundle[@"CFBundleIdentifier"];
    if (!bundleID) return [self removeItem];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/dpkg";
    task.arguments = @[@"-r", bundleID];
    [task launch];
    [task waitUntilExit];
    return task.terminationStatus == 0;
}

- (void)openInFilza {
    NSString *urlStr = [NSString stringWithFormat:@"filza://view%@", self.path.path];
    NSURL *url = [NSURL URLWithString:[urlStr stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)removeOrUninstallItem {
    if (self.isApplication && self.applicationBundle && [self isApplicationInstalled]) {
        [self uninstallItem];
    } else {
        [self removeItem];
    }
}

- (NSDictionary *)lsApplicationInfo {
    return [DPApplicationUtility applicationInfoForBundleIdentifier:(NSString *)self.applicationBundle];
}

- (UIViewController *)infoViewController {
    // Returns a simple detail VC populated with urlInfo
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor systemBackgroundColor];
    vc.title = self.displayName;
    return vc;
}

- (UIViewController *)embeddedInfoViewController {
    UIViewController *info = [self infoViewController];
    return [[UINavigationController alloc] initWithRootViewController:info];
}

- (UIViewController *)previewController {
    return [DPPreviewViewController previewControllerWithInfo:self];
}

- (UIViewController *)embeddedPreviewController {
    UIViewController *preview = [self previewController];
    return [[UINavigationController alloc] initWithRootViewController:preview];
}

@end
