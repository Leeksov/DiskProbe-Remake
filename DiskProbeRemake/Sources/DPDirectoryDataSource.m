#import "DPDirectoryDataSource.h"
#import "DPUserPreferences.h"
#import "DPCatalog.h"
#import "DPHelper.h"

@implementation DPDirectoryDataSource

+ (instancetype)dataSourceWithDelegate:(id<DPDirectoryDataSourceDelegate>)delegate {
    DPDirectoryDataSource *ds = [DPDirectoryDataSource new];
    ds.delegate = delegate;
    return ds;
}

- (void)setDirectory:(NSString *)directory {
    _directory = [directory copy];
    _directoryData = [NSMutableArray new];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSURL *dirURL = [NSURL fileURLWithPath:directory];
            BOOL showHidden = [DPUserPreferences sharedPreferences].showHiddenFiles;
            NSDirectoryEnumerationOptions options = showHidden
                ? NSDirectoryEnumerationSkipsSubdirectoryDescendants
                : (NSDirectoryEnumerationSkipsSubdirectoryDescendants | NSDirectoryEnumerationSkipsHiddenFiles);

            NSArray<NSURLResourceKey> *keys = @[
                NSURLFileSizeKey,
                NSURLContentModificationDateKey,
                NSURLIsSymbolicLinkKey,
                NSURLIsHiddenKey,
                NSURLNameKey,
                NSURLIsDirectoryKey,
            ];

            NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager]
                enumeratorAtURL:dirURL
                includingPropertiesForKeys:keys
                options:options
                errorHandler:nil];

            for (NSURL *itemURL in enumerator) {
                NSNumber *size = nil;
                NSDate *modDate = nil;
                NSNumber *isSymbolic = nil;
                NSNumber *isHidden = nil;
                NSString *itemName = nil;

                [itemURL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
                [itemURL getResourceValue:&modDate forKey:NSURLContentModificationDateKey error:nil];
                [itemURL getResourceValue:&isSymbolic forKey:NSURLIsSymbolicLinkKey error:nil];
                [itemURL getResourceValue:&isHidden forKey:NSURLIsHiddenKey error:nil];
                [itemURL getResourceValue:&itemName forKey:NSURLNameKey error:nil];

                DPPathInfo *info = [DPPathInfo pathInfoWithURL:itemURL
                                                        bytes:[size unsignedLongLongValue]
                                                 modification:modDate
                                                     symbolic:[isSymbolic boolValue]
                                                       hidden:[isHidden boolValue]];
                [self.directoryData addObject:info];
            }

            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:directory error:nil];
            NSNumber *bytes = [NSNumber numberWithUnsignedLongLong:[attrs fileSize]];
            NSDate *modDate = [attrs fileModificationDate];
            NSString *fileType = [attrs fileType];
            BOOL symbolic = [fileType isEqualToString:NSFileTypeSymbolicLink];
            NSString *last = [dirURL lastPathComponent];
            DPPathInfo *parentInfo = [DPPathInfo pathInfoWithURL:dirURL
                                                          bytes:[bytes unsignedLongLongValue]
                                                   modification:modDate
                                                       symbolic:symbolic
                                                         hidden:[last hasPrefix:@"."]];
            self.pathInfo = parentInfo;

            dispatch_async(dispatch_get_main_queue(), ^{
                [self _sortAndNotify:NO];
                [self _didChangeDirectory];
            });
        }
    });
}

- (void)setFilter:(NSString *)filter {
    _filter = [filter copy];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            if (filter && filter.length) {
                NSInteger searchMode = [DPUserPreferences sharedPreferences].searchMode;
                NSString *fmt = (searchMode != 0)
                    ? @"SELF.displayName CONTAINS[cd] %@"
                    : @"SELF.displayName BEGINSWITH[cd] %@";
                NSPredicate *pred = [NSPredicate predicateWithFormat:fmt, filter];
                NSArray *filtered = [self->_directoryData filteredArrayUsingPredicate:pred];
                self->_filteredData = [filtered mutableCopy];
            } else {
                self->_filteredData = nil;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self _filterResultsDidUpdate];
            });
        }
    });
}

- (void)refreshData {
    NSString *dir = self.directory ?: @"/";
    [self setDirectory:dir];
}

- (void)sort {
    [self _sortAndNotify:YES];
}

// Category (DPFilterAlert): 0=Name, 1=Size, 2=Age.
// Direction:                 0=Ascending, 1=Descending.
static DPSortingMode DPModeFor(NSInteger cat, NSInteger dir) {
    BOOL asc = (dir == 0);
    switch (cat) {
        case 0: return asc ? DPSortingModeNameAsc : DPSortingModeNameDesc;
        case 1: return asc ? DPSortingModeSizeAsc : DPSortingModeSizeDesc;
        case 2: return asc ? DPSortingModeDateAsc : DPSortingModeDateDesc;
        default: return DPSortingModeNameAsc;
    }
}

- (void)sortIfNeeded {
    NSInteger cat = [DPUserPreferences sharedPreferences].pathSortingCategory;
    NSInteger dir = [DPUserPreferences sharedPreferences].pathSortingDirection;
    DPSortingMode mode = DPModeFor(cat, dir);
    if ((NSInteger)mode != (NSInteger)self.sortingMode) {
        [self setSortingMode:mode];
        [self _didChangeSortingMode];
    }
}

- (void)_sortAndNotify:(BOOL)notify {
    NSInteger cat = [DPUserPreferences sharedPreferences].pathSortingCategory;
    NSInteger dir = [DPUserPreferences sharedPreferences].pathSortingDirection;
    [self setSortingMode:DPModeFor(cat, dir)];
    if (notify) [self _didChangeSortingMode];
}

- (void)setSortingMode:(DPSortingMode)sortingMode {
    _sortingMode = sortingMode;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            BOOL foldersOnTop = [DPUserPreferences sharedPreferences].foldersOnTop;
            BOOL asc = (sortingMode == DPSortingModeNameAsc ||
                        sortingMode == DPSortingModeSizeAsc ||
                        sortingMode == DPSortingModeDateAsc);
            DPCatalog *catalog = [DPCatalog sharedCatalog];

            NSSortDescriptor *dirDesc = [NSSortDescriptor sortDescriptorWithKey:@"isDirectory" ascending:NO];

            NSSortDescriptor *nameDesc = [NSSortDescriptor sortDescriptorWithKey:@"displayName"
                                                                       ascending:asc
                                                                      comparator:^NSComparisonResult(id a, id b) {
                return [a localizedCaseInsensitiveCompare:b];
            }];

            // Sort by effective bytes: directory → cached catalog size, file → bytes.
            NSComparator sizeCmp = ^NSComparisonResult(DPPathInfo *a, DPPathInfo *b) {
                unsigned long long aB = a.isDirectory ? [catalog sizeForPath:(a.isSymbolicLink && a.symbolicPath ? a.symbolicPath.path : a.path.path)] : a.bytes;
                unsigned long long bB = b.isDirectory ? [catalog sizeForPath:(b.isSymbolicLink && b.symbolicPath ? b.symbolicPath.path : b.path.path)] : b.bytes;
                if (aB < bB) return NSOrderedAscending;
                if (aB > bB) return NSOrderedDescending;
                return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
            };

            NSSortDescriptor *dateDesc = [NSSortDescriptor sortDescriptorWithKey:@"modificationDate"
                                                                       ascending:asc
                                                                      comparator:^NSComparisonResult(id a, id b) {
                if (!a && !b) return NSOrderedSame;
                if (!a) return NSOrderedAscending;
                if (!b) return NSOrderedDescending;
                return [a compare:b];
            }];

            NSArray *descriptors = nil;
            switch (sortingMode) {
                case DPSortingModeNameAsc:
                case DPSortingModeNameDesc:
                    descriptors = foldersOnTop ? @[dirDesc, nameDesc] : @[nameDesc];
                    break;
                case DPSortingModeDateAsc:
                case DPSortingModeDateDesc:
                    descriptors = foldersOnTop ? @[dirDesc, dateDesc, nameDesc] : @[dateDesc, nameDesc];
                    break;
                case DPSortingModeSizeAsc:
                case DPSortingModeSizeDesc:
                    // No built-in descriptor works for dir-vs-file cached size — custom comparator below.
                    descriptors = foldersOnTop ? @[dirDesc] : nil;
                    break;
                default:
                    descriptors = @[nameDesc];
                    break;
            }

            NSMutableArray *data = (NSMutableArray *)[self data];
            if (sortingMode == DPSortingModeSizeAsc || sortingMode == DPSortingModeSizeDesc) {
                if (foldersOnTop) [data sortUsingDescriptors:@[dirDesc]];
                NSComparator cmp = asc ? sizeCmp : ^NSComparisonResult(id a, id b) {
                    NSComparisonResult r = sizeCmp(a, b);
                    return (NSComparisonResult)(-(int)r);
                };
                if (foldersOnTop) {
                    // Sort folders and files separately to keep folders on top.
                    NSMutableArray *dirs = [NSMutableArray new];
                    NSMutableArray *files = [NSMutableArray new];
                    for (DPPathInfo *p in data) {
                        if (p.isDirectory) [dirs addObject:p]; else [files addObject:p];
                    }
                    [dirs sortUsingComparator:cmp];
                    [files sortUsingComparator:cmp];
                    [data removeAllObjects];
                    [data addObjectsFromArray:dirs];
                    [data addObjectsFromArray:files];
                } else {
                    [data sortUsingComparator:cmp];
                }
            } else if (descriptors) {
                [data sortUsingDescriptors:descriptors];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationDidSortData" object:nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationDidRefreshData" object:nil];
                self.seed = arc4random_uniform(0x15F8F) + 10000;
            });
        }
    });
}

- (void)_didChangeDirectory {
    id<DPDirectoryDataSourceDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(didChangeDirectory:)]) {
        [delegate didChangeDirectory:self.directory];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationDidRefreshData" object:nil];
}

- (void)_didChangeSortingMode {
    id<DPDirectoryDataSourceDelegate> delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(didChangeSortingMode:)]) {
        [delegate didChangeSortingMode:self.sortingMode];
    }
}

- (void)_filterResultsDidUpdate {
    id delegate = self.delegate;
    if (delegate && [delegate respondsToSelector:@selector(filterResultsDidUpdate)]) {
        [delegate performSelector:@selector(filterResultsDidUpdate)];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationDidRefreshData" object:nil];
}

- (NSIndexPath *)indexPathForInfo:(DPPathInfo *)info {
    NSUInteger idx = [[self data] indexOfObject:info];
    return [NSIndexPath indexPathForRow:idx inSection:0];
}

- (DPPathInfo *)infoAtIndexPath:(NSIndexPath *)indexPath {
    return [[self data] objectAtIndexedSubscript:indexPath.row];
}

- (NSArray<DPPathInfo *> *)data {
    if (_filter && _filter.length && _filteredData) {
        return _filteredData;
    }
    return _directoryData;
}

@end
