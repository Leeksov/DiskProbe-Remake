#import "DPHelper.h"
#import "DPFastScanner.h"

// NSTask is SPI on iOS; declare the minimal selectors we use.
@interface NSTask : NSObject
- (instancetype)init;
@property (copy) NSString *launchPath;
@property (copy) NSArray<NSString *> *arguments;
@property (retain) id standardOutput;
@property (retain) id standardError;
- (void)launch;
- (void)waitUntilExit;
@property (readonly) int terminationStatus;
@end

static NSDictionary *_mountedVolumes;
static NSArray *_permissionsTable;

@implementation DPHelper

+ (NSString *)displayStringForTimeInterval:(NSTimeInterval)interval {
    return [self displayStringForTimeInterval:interval style:0];
}

+ (NSString *)displayStringForTimeInterval:(NSTimeInterval)interval style:(NSInteger)style {
    NSDateComponentsFormatter *fmt = [[NSDateComponentsFormatter alloc] init];
    fmt.unitsStyle = (style == 0) ? NSDateComponentsFormatterUnitsStyleAbbreviated
                                  : NSDateComponentsFormatterUnitsStyleFull;
    fmt.allowedUnits = NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
    fmt.maximumUnitCount = 2;
    return [fmt stringFromTimeInterval:interval] ?: @"0s";
}

+ (NSDateFormatter *)fileModificationDateFormatter {
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateStyle = NSDateFormatterShortStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
    });
    return fmt;
}

+ (NSString *)displayStringForDate:(NSDate *)date {
    return [self displayStringForDate:date style:0];
}

+ (NSString *)displayStringForDate:(NSDate *)date style:(NSInteger)style {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    if (style == 0) {
        fmt.dateStyle = NSDateFormatterShortStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
    } else {
        fmt.dateStyle = NSDateFormatterLongStyle;
        fmt.timeStyle = NSDateFormatterLongStyle;
    }
    return [fmt stringFromDate:date] ?: @"—";
}

+ (NSString *)permissionsStringForAttributes:(NSDictionary *)attributes {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // rwx per octet
        _permissionsTable = @[
            @"---", @"--x", @"-w-", @"-wx",
            @"r--", @"r-x", @"rw-", @"rwx"
        ];
    });
    NSMutableString *result = [NSMutableString string];
    NSString *fileType = attributes[NSFileType];
    [result appendString:[fileType isEqualToString:NSFileTypeDirectory] ? @"d" : @"-"];
    NSUInteger perms = [attributes[NSFilePosixPermissions] unsignedIntegerValue];
    for (int shift = 6; shift >= 0; shift -= 3) {
        [result appendString:_permissionsTable[(perms >> shift) & 7]];
    }
    return [result copy];
}

+ (NSString *)mimeTypeForFile:(NSString *)path {
    NSString *ext = path.pathExtension.lowercaseString;
    NSDictionary *map = @{
        @"jpg": @"image/jpeg", @"jpeg": @"image/jpeg",
        @"png": @"image/png", @"gif": @"image/gif",
        @"mp4": @"video/mp4", @"mov": @"video/quicktime",
        @"mp3": @"audio/mpeg", @"m4a": @"audio/mp4",
        @"pdf": @"application/pdf",
        @"zip": @"application/zip",
        @"txt": @"text/plain", @"html": @"text/html",
        @"plist": @"application/x-plist",
    };
    return map[ext] ?: @"application/octet-stream";
}

+ (CGFloat)screenScale {
    return [UIScreen mainScreen].scale;
}

+ (void)logMemoryPressure {
    NSLog(@"[DiskProbe] Memory pressure noted");
}

+ (void)writeDebugFiles {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDir = [[paths firstObject] stringByAppendingPathComponent:@"com.creaturecoding.diskprobe"];
    NSString *debugDir = [cacheDir stringByAppendingPathComponent:@"debug"];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:debugDir]) {
        [fm createDirectoryAtPath:debugDir withIntermediateDirectories:NO attributes:nil error:nil];
    }

    NSData *payload = [@"TEST_FILE" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attrs = @{
        NSFileOwnerAccountID: @(501),
        NSFileGroupOwnerAccountID: @(501),
    };

    for (int i = 0; i < 4000; i++) {
        NSString *name = [NSString stringWithFormat:@"%d.txt", i];
        NSString *filePath = [debugDir stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] createFileAtPath:filePath contents:payload attributes:attrs];
    }
}

+ (void)fixCachePermissions {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDir = [[paths firstObject] stringByAppendingPathComponent:@"com.creaturecoding.diskprobe"];
    NSURL *cacheURL = [NSURL fileURLWithPath:cacheDir];

    NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:cacheURL
                                 includingPropertiesForKeys:nil
                                                    options:0
                                               errorHandler:nil];

    NSFileManager *setter = [NSFileManager defaultManager];
    for (NSURL *fileURL in enumerator) {
        NSDictionary *current = [setter attributesOfItemAtPath:fileURL.path error:nil];
        NSMutableDictionary *attrs = [current mutableCopy];
        [attrs setValue:@(501) forKey:NSFileOwnerAccountID];
        [attrs setValue:@(501) forKey:NSFileGroupOwnerAccountID];
        [setter setAttributes:attrs ofItemAtPath:fileURL.path error:nil];
    }
}

+ (id)displayValueForNSURLResourceKey:(NSString *)key inValue:(id)value {
    // Boolean-valued NSURLResourceKeys → localized YES/NO
    NSSet *boolKeys = [NSSet setWithArray:@[
        NSURLIsRegularFileKey, NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey,
        NSURLIsVolumeKey, NSURLIsPackageKey, NSURLIsSystemImmutableKey,
        NSURLIsUserImmutableKey, NSURLIsHiddenKey, NSURLHasHiddenExtensionKey,
        NSURLIsReadableKey, NSURLIsWritableKey, NSURLIsExecutableKey,
        NSURLIsMountTriggerKey, NSURLIsExcludedFromBackupKey,
    ]];
    // Date-valued keys
    NSSet *dateKeys = [NSSet setWithArray:@[
        NSURLCreationDateKey, NSURLContentAccessDateKey,
        NSURLContentModificationDateKey, NSURLAttributeModificationDateKey,
        NSURLAddedToDirectoryDateKey,
    ]];
    // Number-valued keys that should be stringValue
    NSSet *numberKeys = [NSSet setWithArray:@[
        NSURLFileSizeKey, NSURLFileAllocatedSizeKey, NSURLLinkCountKey,
        NSURLPreferredIOBlockSizeKey,
    ]];
    // Path-like keys (NSURL)
    NSSet *pathKeys = [NSSet setWithArray:@[
        NSURLParentDirectoryURLKey, NSURLVolumeURLKey,
    ]];
    // Plain-string NSURLResourceKeys — pass through if non-empty
    NSSet *stringKeys = [NSSet setWithArray:@[
        NSURLNameKey, NSURLLocalizedNameKey,
        NSURLPathKey, NSURLCanonicalPathKey,
        NSURLTypeIdentifierKey, NSURLLocalizedTypeDescriptionKey,
    ]];

    if ([stringKeys containsObject:key]) {
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value length]) return value;
        return @"???";
    }
    if ([boolKeys containsObject:key]) {
        if (![value isKindOfClass:[NSNumber class]]) return @"???";
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *raw = [value boolValue] ? @"YES" : @"NO";
        return [bundle localizedStringForKey:raw value:@"" table:nil];
    }
    if ([dateKeys containsObject:key]) {
        if (![value isKindOfClass:[NSDate class]]) return @"???";
        return [DPHelper displayStringForDate:value];
    }
    if ([numberKeys containsObject:key]) {
        if (![value isKindOfClass:[NSNumber class]]) return @"???";
        return [value stringValue];
    }
    if ([pathKeys containsObject:key]) {
        if ([value isKindOfClass:[NSURL class]] && [[(NSURL *)value path] length]) return [value path];
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value length]) return value;
        return @"???";
    }
    // Document identifier — typically NSNumber on supporting filesystems.
    if ([key isEqualToString:NSURLDocumentIdentifierKey]) {
        if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value length]) return value;
        return @"???";
    }
    return @"???";
}

+ (NSNumber *)sizeOfDirectory:(NSString *)path {
    return [self sizeOfDirectory:path dataSource:nil];
}

+ (NSNumber *)sizeOfDirectory:(NSString *)path dataSource:(NSMutableDictionary *)dataSource {
    // Fast path: getattrlistbulk(2) + parallel first-level walks. Typically
    // 10-50x faster than NSDirectoryEnumerator for large trees.
    unsigned long long total = DPFastDirectorySize(path.fileSystemRepresentation);

    if (total == 0) {
        // Fast scanner returned 0 — either the tree really is empty, the
        // filesystem doesn't support getattrlistbulk (ENOTSUP), or open
        // failed. Fall back to NSDirectoryEnumerator so we don't report
        // 0 for a non-empty (but slow-to-query) tree.
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *url = [NSURL fileURLWithPath:path];
        NSArray *keys = @[NSURLFileAllocatedSizeKey, NSURLIsSymbolicLinkKey, NSURLIsRegularFileKey];
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:url
                                    includingPropertiesForKeys:keys
                                                       options:0
                                                  errorHandler:^BOOL(NSURL *u, NSError *e) {
            return YES;
        }];
        for (NSURL *fileURL in enumerator) {
            NSNumber *isSymlink = nil;
            NSNumber *isRegular = nil;
            NSNumber *sizeNum = nil;
            [fileURL getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:NULL];
            if (isSymlink.boolValue) continue;
            [fileURL getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:NULL];
            if (!isRegular.boolValue) continue;
            [fileURL getResourceValue:&sizeNum forKey:NSURLFileAllocatedSizeKey error:NULL];
            total += sizeNum.unsignedLongLongValue;
        }
    }

    NSNumber *result = @(total);
    if (dataSource) {
        [dataSource setValue:result forKey:path];
    }
    return result;
}

+ (NSDictionary *)mountedVolumes {
    if (_mountedVolumes) return _mountedVolumes;

    // Run `df -h` and parse output
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/df";
    task.arguments = @[@"-h"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    [task launch];
    [task waitUntilExit];
    NSData *data = pipe.fileHandleForReading.readDataToEndOfFile;
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    NSMutableDictionary *volumes = [NSMutableDictionary dictionaryWithDictionary:@{
        @"/dev": @"devfs",
        @"/": @"/",
    }];

    [output enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        // df line: Filesystem  Size  Used  Avail  Capacity  iused  ifree  %iused  Mounted on
        NSArray *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        parts = [parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        if (parts.count >= 9) {
            NSString *dev = parts[0];
            NSString *mount = parts.lastObject;
            if ([dev hasPrefix:@"/dev/"]) {
                volumes[dev] = mount;
            }
        }
    }];

    _mountedVolumes = [volumes copy];
    return _mountedVolumes;
}

+ (NSString *)formatFileSize:(unsigned long long)bytes {
    if (bytes < 1024) return [NSString stringWithFormat:@"%llu B", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.2f KB", bytes / 1024.0];
    if (bytes < 1024 * 1024 * 1024) return [NSString stringWithFormat:@"%.2f MB", bytes / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}

@end
