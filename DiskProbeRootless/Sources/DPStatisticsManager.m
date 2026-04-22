#import "DPStatisticsManager.h"

@implementation DPStatisticsManager

+ (instancetype)sharedStatistics {
    static DPStatisticsManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[DPStatisticsManager alloc] init];
    });
    return sharedInstance;
}

+ (NSString *)statisticsPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachesDir = [paths firstObject];
    NSString *dir = [cachesDir stringByAppendingPathComponent:@"com.creaturecoding.diskprobe"];
    return [dir stringByAppendingPathComponent:@"statistics.plist"];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *path = [[self class] statisticsPath];
        NSError *dataError = nil;
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&dataError];
        NSDictionary *plist = nil;
        if (data && dataError == nil) {
            NSError *plistError = nil;
            id parsed = [NSPropertyListSerialization propertyListWithData:data
                                                                  options:NSPropertyListImmutable
                                                                   format:NULL
                                                                    error:&plistError];
            if (parsed && plistError == nil) {
                plist = parsed;
            } else {
                NSLog(@"Error: Failed to read statistics plist: %@", [plistError localizedDescription]);
                plist = nil;
            }
        } else {
            NSLog(@"Error: Failed to read statistics plist: %@", [dataError localizedDescription]);
            plist = nil;
        }

        NSMutableDictionary *mutable = [plist mutableCopy];
        if (mutable == nil) {
            mutable = [NSMutableDictionary new];
        }
        _statistics = mutable;
    }
    return self;
}

- (void)updateStatisticsForFileDeletion:(id)fileDeletion size:(NSInteger)size fileCount:(NSInteger)fileCount {
    NSNumber *newBytes = [NSNumber numberWithLong:[self.statistics[@"DPStatisticsTotalBytes"] integerValue] + size];
    self.statistics[@"DPStatisticsTotalBytes"] = newBytes;

    NSNumber *newItems = [NSNumber numberWithLong:[self.statistics[@"DPStatisticsTotalItems"] integerValue] + fileCount];
    self.statistics[@"DPStatisticsTotalItems"] = newItems;
}

- (void)saveStatistics {
    [self.statistics writeToFile:[[self class] statisticsPath] atomically:NO];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = @{
        NSFileOwnerAccountID: [NSNumber numberWithInt:501],
        NSFileGroupOwnerAccountID: [NSNumber numberWithInt:501],
    };
    [fm setAttributes:attrs ofItemAtPath:[[self class] statisticsPath] error:nil];
}

- (NSInteger)totalBytes {
    return [self.statistics[@"DPStatisticsTotalBytes"] integerValue];
}

- (NSInteger)totalItems {
    return [self.statistics[@"DPStatisticsTotalItems"] integerValue];
}

- (NSString *)totalBytesString {
    return [NSByteCountFormatter stringFromByteCount:[self totalBytes] countStyle:NSByteCountFormatterCountStyleFile];
}

- (NSString *)totalItemsString {
    return [NSNumberFormatter localizedStringFromNumber:[NSNumber numberWithInteger:[self totalItems]]
                                            numberStyle:NSNumberFormatterDecimalStyle];
}

@end
