#import "DPPathInfo.h"
#import "DPHelper.h"
#import "DPCatalog.h"
#import "DPApplicationUtility.h"
#import "DPPreviewViewController.h"
#import "DPTableViewController.h"
#import <stdlib.h>
#import <limits.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <CoreServices/CoreServices.h>

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

    // On iOS, -resourceValuesForKeys: often returns nil for many keys on system
    // directories (paths outside the app sandbox). Build a merged dictionary
    // that fills in sensible fallbacks from self.path / file attributes so the
    // Info screen doesn't show "???" for values we can compute locally.
    NSMutableDictionary *merged = [res mutableCopy] ?: [NSMutableDictionary dictionary];

    // NSURLPathKey → self.path.path
    if (!merged[NSURLPathKey] && self.path.path.length) {
        merged[NSURLPathKey] = self.path.path;
    }
    // NSURLCanonicalPathKey → standardized path, then realpath(3)
    if (!merged[NSURLCanonicalPathKey]) {
        NSString *canonical = self.path.URLByStandardizingPath.path;
        if (!canonical.length && self.path.path.length) {
            char resolved[PATH_MAX] = {0};
            if (realpath(self.path.path.fileSystemRepresentation, resolved) != NULL) {
                canonical = [fm stringWithFileSystemRepresentation:resolved length:strlen(resolved)];
            }
        }
        if (canonical.length) merged[NSURLCanonicalPathKey] = canonical;
    }
    // NSURLParentDirectoryURLKey → parent directory URL (display helper calls -path)
    if (!merged[NSURLParentDirectoryURLKey]) {
        NSURL *parent = self.path.URLByDeletingLastPathComponent;
        if (parent) merged[NSURLParentDirectoryURLKey] = parent;
    }
    // NSURLNameKey / NSURLLocalizedNameKey fallbacks
    if (!merged[NSURLNameKey] && self.name.length) {
        merged[NSURLNameKey] = self.name;
    }
    if (!merged[NSURLLocalizedNameKey]) {
        merged[NSURLLocalizedNameKey] = self.displayName ?: self.name ?: @"";
    }
    // NSURLTypeIdentifierKey → compute from extension
    NSString *uti = merged[NSURLTypeIdentifierKey];
    if (!uti.length) {
        NSString *ext = self.path.pathExtension;
        if (ext.length) {
            CFStringRef cfUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                                     (__bridge CFStringRef)ext,
                                                                     NULL);
            if (cfUTI) {
                uti = (__bridge_transfer NSString *)cfUTI;
                if (uti.length) merged[NSURLTypeIdentifierKey] = uti;
            }
        }
        if (!merged[NSURLTypeIdentifierKey]) {
            // Directory / regular-file fallback UTIs
            if ([attrs[NSFileType] isEqualToString:NSFileTypeDirectory]) {
                merged[NSURLTypeIdentifierKey] = (__bridge NSString *)kUTTypeFolder;
            } else if ([attrs[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
                merged[NSURLTypeIdentifierKey] = (__bridge NSString *)kUTTypeSymLink;
            } else if (attrs[NSFileType]) {
                merged[NSURLTypeIdentifierKey] = (__bridge NSString *)kUTTypeData;
            }
        }
    }
    // NSURLLocalizedTypeDescriptionKey → derive from UTI
    if (!merged[NSURLLocalizedTypeDescriptionKey] && [merged[NSURLTypeIdentifierKey] length]) {
        CFStringRef desc = UTTypeCopyDescription((__bridge CFStringRef)merged[NSURLTypeIdentifierKey]);
        if (desc) {
            NSString *d = (__bridge_transfer NSString *)desc;
            if (d.length) merged[NSURLLocalizedTypeDescriptionKey] = d;
        }
    }
    // NSURLAddedToDirectoryDateKey → NSFileCreationDate fallback
    if (!merged[NSURLAddedToDirectoryDateKey] && attrs[NSFileCreationDate]) {
        merged[NSURLAddedToDirectoryDateKey] = attrs[NSFileCreationDate];
    }
    // Date fallbacks from attrs when NSURL didn't return them
    if (!merged[NSURLCreationDateKey] && attrs[NSFileCreationDate]) {
        merged[NSURLCreationDateKey] = attrs[NSFileCreationDate];
    }
    if (!merged[NSURLContentModificationDateKey] && attrs[NSFileModificationDate]) {
        merged[NSURLContentModificationDateKey] = attrs[NSFileModificationDate];
    }
    // FileSize fallback
    if (!merged[NSURLFileSizeKey] && attrs[NSFileSize]) {
        merged[NSURLFileSizeKey] = attrs[NSFileSize];
    }
    // Link count fallback
    if (!merged[NSURLLinkCountKey] && attrs[NSFileReferenceCount]) {
        merged[NSURLLinkCountKey] = attrs[NSFileReferenceCount];
    }
    // IsApplication fallback — use our own detection
    if (!merged[NSURLIsApplicationKey]) {
        merged[NSURLIsApplicationKey] = @(self.isApplication);
    }
    // IsDirectory / IsRegularFile / IsSymbolicLink fallbacks from attrs
    if (!merged[NSURLIsDirectoryKey]) {
        merged[NSURLIsDirectoryKey] = @([attrs[NSFileType] isEqualToString:NSFileTypeDirectory]);
    }
    if (!merged[NSURLIsRegularFileKey]) {
        merged[NSURLIsRegularFileKey] = @([attrs[NSFileType] isEqualToString:NSFileTypeRegular]);
    }
    if (!merged[NSURLIsSymbolicLinkKey]) {
        merged[NSURLIsSymbolicLinkKey] = @([attrs[NSFileType] isEqualToString:NSFileTypeSymbolicLink]);
    }
    if (!merged[NSURLIsHiddenKey]) {
        merged[NSURLIsHiddenKey] = @(self.isHidden);
    }

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
        if (!symPath.length && self.path.path.length) {
            NSString *resolved = [self.path.path stringByResolvingSymlinksInPath];
            symPath = resolved.length ? resolved : self.path.path;
        }
        NSArray *rows = @[
            DPRow(DPLocalized(@"Display Name"),
                  self.displayName, @"subtitle"),
            DPRow(DPLocalized(@"Name"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLNameKey inValue:merged[NSURLNameKey]], @"subtitle"),
            DPRow(DPLocalized(@"Localized Name"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLLocalizedNameKey inValue:merged[NSURLLocalizedNameKey]], @"subtitle"),
            DPRow(DPLocalized(@"Path"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLPathKey inValue:merged[NSURLPathKey]], @"subtitle"),
            DPRow(DPLocalized(@"Absolute Path"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLCanonicalPathKey inValue:merged[NSURLCanonicalPathKey]], @"subtitle"),
            DPRow(DPLocalized(@"Symbolic Path"),
                  symPath, @"subtitle"),
            DPRow(DPLocalized(@"Parent Path"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLParentDirectoryURLKey inValue:merged[NSURLParentDirectoryURLKey]], @"subtitle"),
            DPRow(DPLocalized(@"Parent Volume"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLVolumeURLKey inValue:merged[NSURLVolumeURLKey]], @"subtitle"),
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
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsReadableKey inValue:merged[NSURLIsReadableKey]], @"value1"),
            DPRow(DPLocalized(@"Writable"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsWritableKey inValue:merged[NSURLIsWritableKey]], @"value1"),
            DPRow(DPLocalized(@"Executable"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsExecutableKey inValue:merged[NSURLIsExecutableKey]], @"value1"),
        ];
        [sections addObject:DPSection(DPLocalized(@"Permissions"), rows)];
    }

    // -------- Dates --------
    {
        NSArray *rows = @[
            DPRow(DPLocalized(@"Creation Date"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLCreationDateKey inValue:merged[NSURLCreationDateKey]], @"subtitle"),
            DPRow(DPLocalized(@"Modification Date"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLContentModificationDateKey inValue:merged[NSURLContentModificationDateKey]], @"subtitle"),
            DPRow(DPLocalized(@"Access Date"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLContentAccessDateKey inValue:merged[NSURLContentAccessDateKey]], @"subtitle"),
            DPRow(DPLocalized(@"FS Modification Date"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLAttributeModificationDateKey inValue:merged[NSURLAttributeModificationDateKey]], @"subtitle"),
            DPRow(DPLocalized(@"Added To Directory Date"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLAddedToDirectoryDateKey inValue:merged[NSURLAddedToDirectoryDateKey]], @"subtitle"),
        ];
        [sections addObject:DPSection(DPLocalized(@"Dates"), rows)];
    }

    // -------- File Info --------
    {
        NSNumber *sizeNum = merged[NSURLFileSizeKey];
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
                  [DPHelper displayValueForNSURLResourceKey:NSURLTypeIdentifierKey inValue:merged[NSURLTypeIdentifierKey]], @"subtitle"),
            DPRow(DPLocalized(@"Localized UTI"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLLocalizedTypeDescriptionKey inValue:merged[NSURLLocalizedTypeDescriptionKey]], @"subtitle"),
            DPRow(DPLocalized(@"Block Size"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLPreferredIOBlockSizeKey inValue:merged[NSURLPreferredIOBlockSizeKey]], @"value1"),
            DPRow(DPLocalized(@"Regular File"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsRegularFileKey inValue:merged[NSURLIsRegularFileKey]], @"value1"),
            DPRow(DPLocalized(@"Directory"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsDirectoryKey inValue:merged[NSURLIsDirectoryKey]], @"value1"),
            DPRow(DPLocalized(@"Symbolic Link"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsSymbolicLinkKey inValue:merged[NSURLIsSymbolicLinkKey]], @"value1"),
            DPRow(DPLocalized(@"Hidden"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsHiddenKey inValue:merged[NSURLIsHiddenKey]], @"value1"),
            DPRow(DPLocalized(@"Hidden Extension"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLHasHiddenExtensionKey inValue:merged[NSURLHasHiddenExtensionKey]], @"value1"),
            DPRow(DPLocalized(@"Volume Root"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsVolumeKey inValue:merged[NSURLIsVolumeKey]], @"value1"),
            DPRow(DPLocalized(@"Application Root"),
                  (self.isApplication && [self.applicationBundle isKindOfClass:[NSDictionary class]] && [(NSDictionary *)self.applicationBundle objectForKey:@"CFBundleIdentifier"])
                      ? [(NSDictionary *)self.applicationBundle objectForKey:@"CFBundleIdentifier"]
                      : [DPHelper displayValueForNSURLResourceKey:NSURLIsApplicationKey inValue:merged[NSURLIsApplicationKey]], @"value1"),
            DPRow(DPLocalized(@"System Immutable"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsSystemImmutableKey inValue:merged[NSURLIsSystemImmutableKey]], @"value1"),
            DPRow(DPLocalized(@"User Immutable"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsUserImmutableKey inValue:merged[NSURLIsUserImmutableKey]], @"value1"),
            DPRow(DPLocalized(@"User Immutable"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsMountTriggerKey inValue:merged[NSURLIsMountTriggerKey]], @"value1"),
            DPRow(DPLocalized(@"Hard Link Count"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLLinkCountKey inValue:merged[NSURLLinkCountKey]], @"value1"),
            DPRow(DPLocalized(@"Backup Excluded"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLIsExcludedFromBackupKey inValue:merged[NSURLIsExcludedFromBackupKey]], @"value1"),
            DPRow(DPLocalized(@"Document ID"),
                  [DPHelper displayValueForNSURLResourceKey:NSURLDocumentIdentifierKey inValue:merged[NSURLDocumentIdentifierKey]], @"value1"),
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
    NSDictionary *data = [self urlInfo];
    DPTableViewController *vc = [DPTableViewController tableViewControllerWithDataSource:data
                                                                              cellStyle:UITableViewCellStyleSubtitle];
    vc.title = self.displayName;
    vc.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:vc
                                                      action:@selector(dismiss)];
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
