#import <Foundation/Foundation.h>
#import "DPPathInfo.h"

@class DPDirectoryDataSource;

@protocol DPDirectoryDataSourceDelegate <NSObject>
@optional
- (void)didChangeDirectory:(NSString *)directory;
- (void)didChangeSortingMode:(NSInteger)mode;
- (void)filterResultsDidUpdate;
@end

typedef NS_ENUM(NSInteger, DPSortingMode) {
    DPSortingModeNameAsc       = 0,
    DPSortingModeNameDesc      = 1,
    DPSortingModeSizeAsc       = 2,
    DPSortingModeSizeDesc      = 3,
    DPSortingModeDateAsc       = 4,
    DPSortingModeDateDesc      = 5,
    DPSortingModeNone          = 99,
};

@interface DPDirectoryDataSource : NSObject

@property (nonatomic, copy) NSString *directory;
@property (nonatomic, copy) NSString *filter;
@property (nonatomic, strong, readonly) NSArray<DPPathInfo *> *data;
@property (nonatomic, strong) NSMutableArray<DPPathInfo *> *directoryData;
@property (nonatomic, strong) NSMutableArray<DPPathInfo *> *filteredData;
@property (nonatomic, strong) DPPathInfo *pathInfo;
@property (nonatomic, assign) DPSortingMode sortingMode;
@property (nonatomic, weak) id<DPDirectoryDataSourceDelegate> delegate;
@property (nonatomic, assign) NSInteger seed;

+ (instancetype)dataSourceWithDelegate:(id<DPDirectoryDataSourceDelegate>)delegate;

- (void)refreshData;
- (void)sort;
- (void)sortIfNeeded;
- (DPPathInfo *)infoAtIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *)indexPathForInfo:(DPPathInfo *)info;

@end
