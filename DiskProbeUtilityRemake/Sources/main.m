#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <sys/stat.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>
#import <signal.h>
#import <stdatomic.h>
#import "DPFastScanner.h"

static NSMutableDictionary *gVolumeInfo = nil;
static NSString *gCatalogPath = nil;
static NSOperationQueue *gOperationQueue = nil;
static NSMutableArray *gArguments = nil;
static BOOL gCompress = NO;
static BOOL gLoading = NO;
static CFTimeInterval gStartTime = 0;
static CFTimeInterval gScanDuration = 0;

static NSString *resultsForCmd(NSString *cmd);
static NSDictionary *getMountedVolumes(void);
static NSMutableDictionary *scanVolumes(void);
static NSNumber *sizeOfDirectory(NSString *path, NSMutableDictionary *dict, NSArray *excluded);
static NSArray *parentPathsForPath(NSString *path);
static void scanMountedVolumes(void);
static void setLoadingState(BOOL loading);
static BOOL saveCacheInfo(void);

static NSString *const kLockPath = @"/var/mobile/Library/Caches/com.leeksov.diskprobe/.diskprobe-utility_pid.lock";
static NSString *const kDefaultCatalogPath = @"/var/mobile/Library/Caches/com.leeksov.diskprobe/diskprobe.catalog";
static NSString *const kCacheDir = @"/var/mobile/Library/Caches/com.leeksov.diskprobe";

#pragma mark - Helpers

static NSString *resultsForCmd(NSString *cmd) {
    FILE *pipe = popen([cmd UTF8String], "r");
    if (!pipe) {
        return [NSString stringWithFormat:@"ERROR PROCESSING COMMAND: %@", cmd];
    }
    NSMutableString *output = [NSMutableString string];
    char buf[1024];
    while (fgets(buf, sizeof(buf), pipe)) {
        NSString *line = [NSString stringWithUTF8String:buf];
        if (line) [output appendString:line];
    }
    pclose(pipe);
    return [NSString stringWithString:output];
}

static NSDictionary *getMountedVolumes(void) {
    NSString *df = resultsForCmd(@"df -h");
    NSMutableDictionary *volumes = [@{@"/dev": @"devfs", @"/": @"/"} mutableCopy];
    [df enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        if ([line hasPrefix:@"Filesystem"]) return;
        NSArray *comps = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (comps.count >= 2) {
            NSString *dev = [comps firstObject];
            NSString *mount = [comps lastObject];
            volumes[mount] = dev;
        }
    }];
    return [volumes copy];
}

static NSArray *parentPathsForPath(NSString *path) {
    NSMutableArray *result = [NSMutableArray new];
    NSString *parent = [path stringByDeletingLastPathComponent];
    while (![path isEqualToString:parent]) {
        [result addObject:parent];
        path = parent;
        parent = [parent stringByDeletingLastPathComponent];
    }
    return result;
}

typedef struct {
    void *dictPtr;   // NSMutableDictionary *
    _Atomic unsigned long long totalItems;
} scan_ctx_t;

static void fast_scan_cb(const char *path,
                         unsigned long long totalBytes,
                         unsigned long long totalItems,
                         void *ctx) {
    scan_ctx_t *c = (scan_ctx_t *)ctx;
    NSMutableDictionary *dict = (__bridge NSMutableDictionary *)c->dictPtr;
    NSString *p = [NSString stringWithUTF8String:path];
    if (!p) return;
    @synchronized(dict) {
        dict[p] = @(totalBytes);
    }
    // Items are reported cumulatively per directory by the scanner; we only
    // want the grand total once, so accumulate just the top-level call's
    // items via the caller after DPFastDirectorySizeWithCallback returns.
    (void)totalItems;
}

static NSNumber *sizeOfDirectory(NSString *path, NSMutableDictionary *dict, NSArray *excluded) {
    // Build NULL-terminated excluded paths list (fs-representations).
    const char **excl = NULL;
    NSMutableArray<NSData *> *exclHold = nil;
    if (excluded.count) {
        exclHold = [NSMutableArray arrayWithCapacity:excluded.count];
        excl = (const char **)calloc(excluded.count + 1, sizeof(char *));
        if (excl) {
            size_t n = 0;
            for (NSString *ep in excluded) {
                const char *cs = [ep fileSystemRepresentation];
                if (!cs) continue;
                NSData *d = [NSData dataWithBytes:cs length:strlen(cs) + 1];
                [exclHold addObject:d];
                excl[n++] = (const char *)d.bytes;
            }
            excl[n] = NULL;
        }
    }

    scan_ctx_t c = { .dictPtr = (__bridge void *)dict };
    atomic_init(&c.totalItems, 0);

    const char *cpath = [path fileSystemRepresentation];
    unsigned long long totalBytes = DPFastDirectorySizeWithCallback(cpath, excl, fast_scan_cb, &c);

    if (excl) free(excl);

    if (totalBytes == 0) {
        // Fallback: unsupported filesystem or empty/failed scan. Use the
        // classic NSDirectoryEnumerator walk.
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *url = [NSURL fileURLWithPath:path];
        NSArray *keys = @[NSURLFileSizeKey, NSURLIsSymbolicLinkKey];
        NSDirectoryEnumerator *en = [fm enumeratorAtURL:url
                             includingPropertiesForKeys:keys
                                                options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                           errorHandler:^BOOL(NSURL *u, NSError *err) {
            return YES;
        }];
        uint64_t fbBytes = 0;
        uint64_t fbItems = 0;
        for (NSURL *entry in en) {
            NSString *entryPath = [entry path];
            if ([excluded containsObject:entryPath]) continue;
            NSNumber *fileSize = nil, *isSymlink = nil;
            [entry getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL];
            [entry getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:NULL];
            NSNumber *size = fileSize;
            if ([isSymlink boolValue]) {
                size = sizeOfDirectory(entryPath, dict, excluded);
            }
            fbItems++;
            fbBytes += [size unsignedLongLongValue];
        }
        totalBytes = fbBytes;
        @synchronized(dict) {
            dict[path] = @(totalBytes);
            NSNumber *prev = dict[@"._dp_total_scanned_items"];
            dict[@"._dp_total_scanned_items"] = @([prev unsignedLongLongValue] + fbItems);
        }
        return @(totalBytes);
    }

    // Fast-path success. dict already populated by callback. We don't have
    // a precise per-subpath items count, so we stat-approximate the grand
    // total from the number of entries the callback populated (directories)
    // — close enough for the progress-style ._dp_total_scanned_items field.
    @synchronized(dict) {
        dict[path] = @(totalBytes);
        NSNumber *prev = dict[@"._dp_total_scanned_items"];
        dict[@"._dp_total_scanned_items"] = @([prev unsignedLongLongValue] + dict.count);
    }
    return @(totalBytes);
}

#pragma mark - Scan orchestration

static NSMutableDictionary *scanVolumes(void) {
    NSDictionary *volumes = getMountedVolumes();
    NSArray *mountPoints = [volumes allKeys];
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"SELF != %@", @"/"];
    NSArray *nonRoot = [mountPoints filteredArrayUsingPredicate:pred];

    NSMutableDictionary *output = [NSMutableDictionary new];
    __block uint64_t collectiveSize = 0;

    [gOperationQueue setMaxConcurrentOperationCount:mountPoints.count];

    for (NSString *mount in mountPoints) {
        NSArray *exclude = [mount isEqualToString:@"/"] ? nonRoot : @[];
        [gOperationQueue addOperationWithBlock:^{
            NSNumber *size = sizeOfDirectory(mount, output, exclude);
            @synchronized(output) {
                output[mount] = size;
                collectiveSize += [size unsignedLongLongValue];
            }
        }];
    }

    while (gOperationQueue.operationCount > 0) {
        [NSThread sleepForTimeInterval:0.05];
    }

    [gOperationQueue addOperationWithBlock:^{
        @synchronized(output) {
            for (NSString *mount in nonRoot) {
                NSArray *parents = parentPathsForPath(mount);
                uint64_t childSize = [output[mount] unsignedLongLongValue];
                for (NSString *parent in parents) {
                    uint64_t parentSize = [output[parent] unsignedLongLongValue];
                    output[parent] = @(parentSize + childSize);
                }
            }
            output[@"._dp_total_collective_volume_size"] = @(collectiveSize);
            output[@"._dp_total_scan_time"] = @(CACurrentMediaTime() - gStartTime);
        }
    }];

    while (gOperationQueue.operationCount > 0) {
        [NSThread sleepForTimeInterval:0.05];
    }

    return output;
}

static void setLoadingState(BOOL loading) {
    gLoading = loading;
    printf("%s scanning volumes\n", loading ? "started" : "finished");
    fflush(stdout);
    CFTimeInterval now = CACurrentMediaTime();
    if (loading) {
        gStartTime = now;
    } else {
        gScanDuration = now - gStartTime;
    }
}

static BOOL saveCacheInfo(void) {
    NSError *err = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:gVolumeInfo
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&err];
    if (!data) return NO;

    BOOL ok = NO;
    if (gCompress) {
        NSData *compressed = [data compressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];
        if (compressed) {
            ok = [compressed writeToFile:gCatalogPath atomically:YES];
        }
    }
    if (!ok) {
        ok = [data writeToFile:gCatalogPath atomically:YES];
    }

    NSDictionary *attrs = @{
        NSFileOwnerAccountID: @501,
        NSFileGroupOwnerAccountID: @501,
    };
    [[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:gCatalogPath error:nil];
    return ok;
}

static void scanMountedVolumes(void) {
    if (gLoading || gVolumeInfo != nil) return;

    setLoadingState(YES);
    gVolumeInfo = scanVolumes();
    setLoadingState(NO);

    printf("%s volume info\n", gCompress ? "compressing" : "saving");
    fflush(stdout);

    BOOL ok = saveCacheInfo();
    if (ok) {
        printf("%s volume info to %s\n", gCompress ? "compressed" : "saved", [gCatalogPath UTF8String]);
    } else {
        printf("error saving volume info to %s\n", [gCatalogPath UTF8String]);
    }
    fflush(stdout);
    printf("finished in %.2f seconds\n", gScanDuration);
    fflush(stdout);
}

#pragma mark - Main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Rootless: no libjailbreak. Rely on entitlements + trustcache.
        setuid(0);
        setgid(0);
        if (getuid() != 0 || getgid() != 0) {
            puts("the more you get,\nthe less you are.");
            fflush(stdout);
            return 77;
        }

        [[NSFileManager defaultManager] createDirectoryAtPath:kCacheDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        FILE *lockRead = fopen([kLockPath UTF8String], "r+");
        if (lockRead) {
            int otherPid = -1;
            fscanf(lockRead, "%d", &otherPid);
            if (otherPid >= 1 && otherPid != getpid() && getpgid(otherPid) >= 0) {
                puts("killing other instances of diskprobe-utility.");
                fflush(stdout);
                if (kill(otherPid, 9) != 0) {
                    puts("failed to kill other diskprobe-utility instance.");
                    puts("there can be only one diskprobe-utility instance.");
                    fflush(stdout);
                    fclose(lockRead);
                    return 77;
                }
            }
            fclose(lockRead);
        }

        FILE *lockWrite = fopen([kLockPath UTF8String], "w+");
        if (lockWrite) {
            fprintf(lockWrite, "%d", getpid());
            fclose(lockWrite);
        }

        gCatalogPath = kDefaultCatalogPath;
        gArguments = [NSMutableArray array];

        NSInteger tail = argc - 1;
        for (int i = 0; i < argc; i++) {
            NSString *arg = [[NSString alloc] initWithCString:argv[i] encoding:NSUTF8StringEncoding];
            if (!arg) { tail--; continue; }
            [gArguments addObject:arg];
            if ([arg isEqualToString:@"-c"] || [arg isEqualToString:@"--compress"]) {
                gCompress = YES;
            } else if (argc != 1 && tail == 0) {
                gCatalogPath = arg;
            }
            tail--;
        }

        gOperationQueue = [NSOperationQueue new];
        gOperationQueue.maxConcurrentOperationCount = 5;
        gOperationQueue.name = @"com.leeksov.diskprobe-utility-processor";
        gOperationQueue.qualityOfService = NSQualityOfServiceUtility;
        gOperationQueue.underlyingQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);

        scanMountedVolumes();
    }
    return 0;
}
