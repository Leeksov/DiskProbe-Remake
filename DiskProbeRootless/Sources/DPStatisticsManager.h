#import <Foundation/Foundation.h>

@interface DPStatisticsManager : NSObject

@property (nonatomic, strong) NSMutableDictionary *statistics;

+ (instancetype)sharedStatistics;
+ (NSString *)statisticsPath;

- (void)updateStatisticsForFileDeletion:(id)fileDeletion size:(NSInteger)size fileCount:(NSInteger)fileCount;
- (void)saveStatistics;

- (NSInteger)totalBytes;
- (NSInteger)totalItems;
- (NSString *)totalBytesString;
- (NSString *)totalItemsString;

@end
