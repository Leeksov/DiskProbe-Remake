#import <Foundation/Foundation.h>

// Loading state bitmask
typedef NS_OPTIONS(NSUInteger, DPCatalogLoadingState) {
    DPCatalogLoadingStateInitial     = 1 << 0,
    DPCatalogLoadingStateDirectory   = 1 << 1,
    DPCatalogLoadingStateVolume      = 1 << 2,
    DPCatalogLoadingStateApplication = 1 << 3,
};

@interface DPCatalog : NSObject

+ (instancetype)sharedCatalog;
+ (NSString *)catalogPath;
+ (NSString *)catalogSize;
+ (BOOL)catalogValid;
+ (BOOL)cacheIsLoaded;
+ (void)fetchCatalogs;
+ (void)refetchCatalogs;

// Volume info
- (NSString *)volumeForPath:(NSString *)path;
- (NSString *)usedSpaceStringForVolumeAtPath:(NSString *)path;
- (NSDictionary *)volumeInfoForPath:(NSString *)path;

// Directory size lookup
- (unsigned long long)sizeForPath:(NSString *)path;
- (NSString *)sizeLabelForPath:(NSString *)path;
- (void)computeSizeForPathAsync:(NSString *)path;

// Remove item and update catalog sizes
- (BOOL)removeItemAtURL:(NSURL *)url itemSize:(unsigned long long)size updatingCatalog:(BOOL)update;

// Stats
@property (nonatomic, readonly) NSUInteger totalScannedItems;

// Cache
- (void)saveCache;
- (void)loadCache;

@end
