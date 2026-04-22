#import "DPCatalog.h"
#import "DPHelper.h"
#import "DPUserPreferences.h"
#import "DPStreamingTask.h"
#import <sys/stat.h>

// Rootless-aware catalog path
#ifdef ROOTLESS
#define JB_PREFIX @"/var/jb"
#else
#define JB_PREFIX @""
#endif

#define DP_UTILITY_DIR (JB_PREFIX @"/usr/libexec/diskprobe")
#define DP_UTILITY_CATALOG @"/var/mobile/Library/Caches/com.leeksov.diskprobe/diskprobe.catalog"
#define DP_EXPANDED_CACHE_SUBDIR @"com.leeksov.diskprobe"
#define DP_EXPANDED_CACHE_FILE @"expanded_sizes.plist"
#define DP_EXPANDED_TIMESTAMP_KEY @"._dp_timestamp"

static DPCatalog *_sharedCatalog;

@interface DPCatalog ()
@property (nonatomic, assign) NSUInteger loadingState;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *directorySizes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *volumeInfoMap;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *applicationInfoMap;
@property (nonatomic, strong) dispatch_queue_t catalogQueue;
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingSizePaths;
@property (nonatomic, strong) dispatch_queue_t pendingQueue;
@property (nonatomic, assign) BOOL expandedCacheDirty;
@property (nonatomic, assign) BOOL expandedWriteScheduled;
@end

@implementation DPCatalog

+ (instancetype)sharedCatalog {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _sharedCatalog = [[DPCatalog alloc] init];
    });
    return _sharedCatalog;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _directorySizes = [NSMutableDictionary dictionary];
        _volumeInfoMap = [NSMutableDictionary dictionary];
        _applicationInfoMap = [NSMutableDictionary dictionary];
        _catalogQueue = dispatch_queue_create("com.leeksov.diskprobe.catalog", DISPATCH_QUEUE_SERIAL);
        _pendingSizePaths = [NSMutableSet set];
        _pendingQueue = dispatch_queue_create("com.leeksov.diskprobe.pendingsize", DISPATCH_QUEUE_SERIAL);
        _loadingState = DPCatalogLoadingStateInitial;
    }
    return self;
}

+ (NSString *)catalogPath {
    // Must match the path the diskprobe-utility writes to.
    return DP_UTILITY_CATALOG;
}

+ (NSString *)catalogSize {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[self catalogPath] error:nil];
    return [NSByteCountFormatter stringFromByteCount:[attrs fileSize] countStyle:NSByteCountFormatterCountStyleFile];
}

+ (BOOL)catalogValid {
    NSError *err = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[self catalogPath] error:&err];
    if (!attrs || err) return NO;
    NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:[attrs fileModificationDate]];
    return age < (NSTimeInterval)[DPUserPreferences sharedPreferences].cacheExpirationLimit;
}

+ (BOOL)cacheIsLoaded {
    DPCatalog *c = [self sharedCatalog];
    return (c.loadingState & (DPCatalogLoadingStateDirectory |
                               DPCatalogLoadingStateVolume |
                               DPCatalogLoadingStateApplication)) ==
           (DPCatalogLoadingStateDirectory |
            DPCatalogLoadingStateVolume |
            DPCatalogLoadingStateApplication);
}

+ (void)fetchCatalogs {
    DPCatalog *c = [self sharedCatalog];
    [c loadCache];
    [c loadExpandedSizesCache];
    dispatch_async(c.catalogQueue, ^{
        [c _fetchVolumeInfo];
        [c _fetchDirectoryInfo];
        [c _fetchApplicationInfo];
    });
}

+ (void)refetchCatalogs {
    DPCatalog *c = [self sharedCatalog];
    c.loadingState = DPCatalogLoadingStateInitial;
    [c.directorySizes removeAllObjects];
    [c.volumeInfoMap removeAllObjects];
    [c.applicationInfoMap removeAllObjects];

    // Wipe both on-disk caches: utility mount-scan catalog and app-owned
    // expanded subdirectory-size cache. Otherwise stale entries would be
    // re-loaded on next launch (or next fetchCatalogs) and defeat the refresh.
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:[self catalogPath] error:nil];
    [fm removeItemAtPath:[c _expandedSizesCachePath] error:nil];
    c.expandedCacheDirty = NO;

    [self fetchCatalogs];
}

#pragma mark - Internal fetch

- (void)_fetchVolumeInfo {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *volumeURLs = [fm mountedVolumeURLsIncludingResourceValuesForKeys:@[
        NSURLVolumeNameKey,
        NSURLVolumeTotalCapacityKey,
        NSURLVolumeAvailableCapacityKey,
    ] options:NSVolumeEnumerationSkipHiddenVolumes];

    for (NSURL *url in volumeURLs) {
        NSString *path = url.path;
        NSError *err = nil;
        NSDictionary *attrs = [fm attributesOfFileSystemForPath:path error:&err];
        if (!err && attrs) {
            unsigned long long total = [attrs[NSFileSystemSize] unsignedLongLongValue];
            unsigned long long free  = [attrs[NSFileSystemFreeSize] unsignedLongLongValue];
            unsigned long long used  = total - free;
            self.volumeInfoMap[path] = @{
                @"path": path,
                @"total": [NSString stringWithFormat:@"%llu", total],
                @"free": [NSString stringWithFormat:@"%llu", free],
                @"used": [NSString stringWithFormat:@"%llu", used],
            };
        }
    }
    [self _updateLoadingStateWithState:DPCatalogLoadingStateVolume];
}

- (void)_fetchDirectoryInfo {
    BOOL compressed = [DPUserPreferences sharedPreferences].catalogCacheIsCompressed;
    NSString *arg = compressed ? @"diskprobe-utility --compress" : @"diskprobe-utility";
    NSString *command = [NSString stringWithFormat:@"%@/%@", DP_UTILITY_DIR, arg];

    [DPStreamingTask streamingTaskForCommand:command
                              didRecieveData:^(NSString *chunk, NSString *complete, BOOL finished, int exitCode) {
        if (!finished) {
            NSLog(@"[DiskProbe] utility: %@", chunk);
            return;
        }
        NSData *data = [NSData dataWithContentsOfFile:DP_UTILITY_CATALOG];
        NSDictionary *plist = nil;
        if (data) {
            NSData *decompressed = [data decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];
            if (decompressed) data = decompressed;
            plist = [NSPropertyListSerialization propertyListWithData:data
                                                              options:NSPropertyListImmutable
                                                               format:nil
                                                                error:nil];
        }
        if ([plist isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *ds = [NSMutableDictionary dictionary];
            for (NSString *path in plist) {
                if ([path hasPrefix:@"._dp_"]) continue;
                ds[path] = plist[path];
            }
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self.directorySizes addEntriesFromDictionary:ds];
            });
        }
        [self _updateLoadingStateWithState:DPCatalogLoadingStateDirectory];
    }];
}

- (void)_fetchApplicationInfo {
    // Enumerate installed apps from LSApplicationWorkspace if available, fallback to /Applications
    NSMutableDictionary *appMap = [NSMutableDictionary dictionary];
    NSArray *appPaths = @[@"/Applications",
                          @"/var/containers/Bundle/Application"];
    if (JB_PREFIX.length) {
        appPaths = [appPaths arrayByAddingObject:[JB_PREFIX stringByAppendingString:@"/Applications"]];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *appsDir in appPaths) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:appsDir error:nil];
        for (NSString *name in contents) {
            if (![name hasSuffix:@".app"]) continue;
            NSString *appPath = [appsDir stringByAppendingPathComponent:name];
            NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
            if (!info) continue;
            NSString *bundleID = info[@"CFBundleIdentifier"];
            NSString *appName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: name;
            if (bundleID) {
                appMap[appPath] = @{
                    @"bundleID": bundleID,
                    @"name": appName,
                    @"path": appPath,
                };
            }
        }
    }
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self.applicationInfoMap addEntriesFromDictionary:appMap];
    });
    [self _updateLoadingStateWithState:DPCatalogLoadingStateApplication];
}

- (void)_updateLoadingStateWithState:(DPCatalogLoadingState)state {
    self.loadingState |= state;
    if ([DPCatalog cacheIsLoaded]) {
        [self saveCache];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationRefreshData" object:nil];
        });
    }
}

#pragma mark - Public API

- (NSString *)volumeForPath:(NSString *)path {
    NSDictionary *info = [self volumeInfoForPath:path];
    NSString *mount = info[@"path"];
    if (!mount) return path;
    return [mount isEqualToString:@"/"] ? @"/" : mount.lastPathComponent;
}

- (NSString *)usedSpaceStringForVolumeAtPath:(NSString *)path {
    NSDictionary *info = [self volumeInfoForPath:path];
    if (!info) return @"—";
    unsigned long long used  = [info[@"used"] unsignedLongLongValue];
    unsigned long long total = [info[@"total"] unsignedLongLongValue];
    return [NSString stringWithFormat:@"%@ / %@",
            [DPHelper formatFileSize:used],
            [DPHelper formatFileSize:total]];
}

- (NSDictionary *)volumeInfoForPath:(NSString *)path {
    // Find the deepest mount point that is a prefix of path
    NSString *best = nil;
    NSUInteger bestLen = 0;
    for (NSString *mount in self.volumeInfoMap) {
        if ([path hasPrefix:mount] && mount.length > bestLen) {
            best = mount;
            bestLen = mount.length;
        }
    }
    return best ? self.volumeInfoMap[best] : nil;
}

- (unsigned long long)sizeForPath:(NSString *)path {
    return [self.directorySizes[path] unsignedLongLongValue];
}

- (void)computeSizeForPathAsync:(NSString *)path {
    if (path.length == 0) return;

    // Skip only the fs root itself. Its size is meaningless on iOS (the
    // data volume lives under /private/var and is shown separately via /var).
    // All other directories, including /System and /private, get computed.
    if ([path isEqualToString:@"/"]) return;

    // Already cached?
    if ([self.directorySizes[path] unsignedLongLongValue] > 0) return;

    __block BOOL shouldDispatch = NO;
    @synchronized (self.pendingSizePaths) {
        if (![self.pendingSizePaths containsObject:path]) {
            [self.pendingSizePaths addObject:path];
            shouldDispatch = YES;
        }
    }
    if (!shouldDispatch) return;

    BOOL wantsBackground = [DPUserPreferences sharedPreferences].keepRunningInBackground;
    UIApplication *app = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier taskID = UIBackgroundTaskInvalid;
    if (wantsBackground) {
        taskID = [app beginBackgroundTaskWithName:@"DPCatalogSize" expirationHandler:^{
            if (taskID != UIBackgroundTaskInvalid) {
                [app endBackgroundTask:taskID];
                taskID = UIBackgroundTaskInvalid;
            }
        }];
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSNumber *size = [DPHelper sizeOfDirectory:path dataSource:nil];
        unsigned long long bytes = [size unsignedLongLongValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (bytes > 0) {
                // Only set the leaf path. Ancestors in directorySizes are mount
                // totals from the utility and should not be updated.
                self.directorySizes[path] = @(bytes);
                // Mark expanded-size cache dirty and schedule a debounced
                // write so sizes survive a relaunch without pegging flash IO.
                self.expandedCacheDirty = YES;
                [self _scheduleExpandedSizesCacheWrite];
            }
            @synchronized (self.pendingSizePaths) {
                [self.pendingSizePaths removeObject:path];
            }
            [self _scheduleRefreshNotification];
            if (taskID != UIBackgroundTaskInvalid) {
                [app endBackgroundTask:taskID];
                taskID = UIBackgroundTaskInvalid;
            }
        });
    });
}

// Coalesce DPNotificationRefreshData posts so cell reloads don't flood the
// main thread during batch directory sizing. First compute schedules a post
// in 400 ms; subsequent computes within that window coalesce. After post the
// flag resets so a new burst of computes will schedule the next post.
- (void)_scheduleRefreshNotification {
    static BOOL scheduled = NO;
    @synchronized (self) {
        if (scheduled) return;
        scheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @synchronized (self) {
            scheduled = NO;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationRefreshData" object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationDidRefreshData" object:nil];
    });
}

- (NSString *)sizeLabelForPath:(NSString *)path {
    unsigned long long sz = [self sizeForPath:path];
    if (sz == 0) return @"—";
    return [DPHelper formatFileSize:sz];
}

- (BOOL)removeItemAtURL:(NSURL *)url itemSize:(unsigned long long)size updatingCatalog:(BOOL)update {
    NSError *err = nil;
    [[NSFileManager defaultManager] removeItemAtURL:url error:&err];
    if (err) return NO;
    if (update) {
        // Walk up and subtract size from parent directories
        NSString *path = url.path.stringByDeletingLastPathComponent;
        while (path.length > 1) {
            NSNumber *existing = self.directorySizes[path];
            if (existing) {
                unsigned long long newSize = existing.unsignedLongLongValue - size;
                self.directorySizes[path] = @(newSize);
            }
            path = path.stringByDeletingLastPathComponent;
        }
        // On-disk expanded cache is now stale for the affected ancestors;
        // schedule a rewrite so the subtraction survives a relaunch.
        self.expandedCacheDirty = YES;
        [self _scheduleExpandedSizesCacheWrite];
    }
    return YES;
}

#pragma mark - Stats

- (NSUInteger)totalScannedItems {
    return self.directorySizes.count + self.volumeInfoMap.count + self.applicationInfoMap.count;
}

#pragma mark - Cache

- (void)saveCache {
    // Match utility output: flat {path: NSNumber(bytes)} binary plist, optionally LZFSE-compressed.
    NSString *path = [DPCatalog catalogPath];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:self.directorySizes
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:nil];
    if (!data) return;

    BOOL wrote = NO;
    if ([DPUserPreferences sharedPreferences].catalogCacheIsCompressed) {
        NSData *compressed = [data compressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];
        if (compressed) wrote = [compressed writeToFile:path atomically:YES];
    }
    if (!wrote) {
        [data writeToFile:path atomically:YES];
    }
}

- (void)loadCache {
    NSString *path = [DPCatalog catalogPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;

    // Try decompressing first
    NSData *decompressed = [data decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];
    if (decompressed) data = decompressed;

    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data
                                                                    options:NSPropertyListImmutable
                                                                     format:nil
                                                                      error:nil];
    if (![plist isKindOfClass:[NSDictionary class]]) return;

    // Flat {path: NSNumber bytes} with optional "._dp_*" metadata keys.
    for (NSString *key in plist) {
        if ([key hasPrefix:@"._dp_"]) continue;
        self.directorySizes[key] = plist[key];
    }
}

#pragma mark - Expanded-sizes cache (app-owned)

// Debounce expanded-size cache writes: during a batch of async computes we
// may see dozens of completions per second. Coalesce into a single write at
// most every 2 seconds so we don't churn the flash.
- (void)_scheduleExpandedSizesCacheWrite {
    @synchronized (self) {
        if (self.expandedWriteScheduled) return;
        self.expandedWriteScheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @synchronized (self) {
            self.expandedWriteScheduled = NO;
        }
        if (self.expandedCacheDirty) {
            [self saveExpandedSizesCache];
        }
    });
}

// App-sandbox Caches-dir path. Unlike the utility catalog, writes here
// don't need the setuid helper. Persists async-computed subdirectory sizes
// across launches.
- (NSString *)_expandedSizesCachePath {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *base = dirs.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [base stringByAppendingPathComponent:DP_EXPANDED_CACHE_SUBDIR];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return [dir stringByAppendingPathComponent:DP_EXPANDED_CACHE_FILE];
}

- (void)saveExpandedSizesCache {
    // Snapshot the current directorySizes. directorySizes is mutated on
    // main; this method is expected to be called on main (debounce timer
    // dispatches there). Skip service keys starting with "._dp_".
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in self.directorySizes) {
        if ([key hasPrefix:@"._dp_"]) continue;
        NSNumber *val = self.directorySizes[key];
        if (![val isKindOfClass:[NSNumber class]]) continue;
        if (val.unsignedLongLongValue == 0) continue; // don't persist empties
        snapshot[key] = val;
    }
    // Stamp so loadExpandedSizesCache can enforce cacheExpirationLimit.
    snapshot[DP_EXPANDED_TIMESTAMP_KEY] = @([NSDate date].timeIntervalSince1970);

    NSError *err = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                                error:&err];
    if (!data) {
        NSLog(@"[DiskProbe] saveExpandedSizesCache: plist serialization failed: %@", err);
        return;
    }
    NSString *path = [self _expandedSizesCachePath];
    if (![data writeToFile:path atomically:YES]) {
        NSLog(@"[DiskProbe] saveExpandedSizesCache: write to %@ failed", path);
        return;
    }
    self.expandedCacheDirty = NO;
}

- (void)loadExpandedSizesCache {
    NSString *path = [self _expandedSizesCachePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return;

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;

    NSError *err = nil;
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data
                                                                    options:NSPropertyListImmutable
                                                                     format:nil
                                                                      error:&err];
    if (![plist isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[DiskProbe] loadExpandedSizesCache: malformed plist at %@ (%@)", path, err);
        return;
    }

    // Honor prefs.cacheExpirationLimit. Default is 3600s (same pref that
    // gates catalogValid). A missing/zero/negative timestamp is treated as
    // stale so a corrupted or pre-versioning file cannot leak sizes past
    // the user's chosen TTL.
    NSTimeInterval limit = (NSTimeInterval)[DPUserPreferences sharedPreferences].cacheExpirationLimit;
    if (limit <= 0) limit = 3600.0;

    NSNumber *tsNum = plist[DP_EXPANDED_TIMESTAMP_KEY];
    NSTimeInterval ts = [tsNum isKindOfClass:[NSNumber class]] ? tsNum.doubleValue : 0.0;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSTimeInterval age = now - ts;

    if (ts <= 0 || age > limit) {
        NSLog(@"[DiskProbe] loadExpandedSizesCache: rejecting stale cache (age=%.0fs, limit=%.0fs) at %@",
              age, limit, path);
        // Remove so we don't keep re-evaluating a dead file.
        [fm removeItemAtPath:path error:nil];
        return;
    }

    NSUInteger merged = 0;
    for (NSString *key in plist) {
        if ([key hasPrefix:@"._dp_"]) continue;
        NSNumber *val = plist[key];
        if (![val isKindOfClass:[NSNumber class]]) continue;
        if (val.unsignedLongLongValue == 0) continue;
        // Don't stomp existing entries (utility mount totals loaded by
        // loadCache just before us — collision in practice is unlikely
        // since utility keys are mount roots, but be safe).
        if (self.directorySizes[key]) continue;
        self.directorySizes[key] = val;
        merged++;
    }
    NSLog(@"[DiskProbe] loadExpandedSizesCache: merged %lu entries (age=%.0fs, limit=%.0fs)",
          (unsigned long)merged, age, limit);
}

@end
