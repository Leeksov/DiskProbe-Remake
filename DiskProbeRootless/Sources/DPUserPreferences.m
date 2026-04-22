#import "DPUserPreferences.h"

static DPUserPreferences *_sharedPreferences;

#define kDPPrefsLastOpenDirectory        @"DPPrefsLastOpenDirectory"
#define kDPPrefsLastOpenVersion          @"DPPrefsLastOpenVersion"
#define kDPPrefsPathViewType             @"DPPrefsPathViewType"
#define kDPPrefsPathSortingMode          @"DPPrefsPathSortingMode"
#define kDPPrefsPathSortingCategory      @"DPPrefsPathSortingCategory"
#define kDPPrefsPathSortingDirection     @"DPPrefsPathSortingDirection"
#define kDPPrefsSearchMode               @"DPPrefsSearchMode"
#define kDPPrefsCacheExpirationLimit     @"DPPrefsCacheExpirationLimit"
#define kDPPrefsInterfaceInteractionType @"DPPrefsInterfaceInteractionType"
#define kDPPrefsContentSize              @"DPPrefsContentSize"
#define kDPPrefsFoldersOnTop             @"DPPrefsFoldersOnTop"
#define kDPPrefsShowHiddenFiles          @"DPPrefsShowHiddenFiles"
#define kDPPrefsCatalogCacheIsCompressed @"DPPrefsCatalogCacheIsCompressed"
#define kDPPrefsKeepRunningInBackground  @"DPPrefsKeepRunningInBackground"

@interface DPUserPreferences ()
@property (nonatomic, strong, readwrite) NSUserDefaults *userDefaults;
@end

@implementation DPUserPreferences

// +[DPUserPreferences sharedPreferences] @ 0x100032178
+ (instancetype)sharedPreferences {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _sharedPreferences = [[DPUserPreferences alloc] initWithUserDefaults:[NSUserDefaults standardUserDefaults]];
    });
    return _sharedPreferences;
}

// -[DPUserPreferences initWithUserDefaults:] @ 0x10003223c
- (instancetype)initWithUserDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        _userDefaults = defaults;
        [self checkDefaults];
    }
    return self;
}

// -[DPUserPreferences synchronize] @ 0x1000322b0
- (void)synchronize {
    [self.userDefaults synchronize];
}

// The 12-element UIContentSizeCategory table indexed by DPPrefsContentSize.
// Matches the memset(0xFF) + individual stores seen in the binary's
// -[DPUserPreferences contentSize] / setContentSize:.
+ (NSArray<UIContentSizeCategory> *)_contentSizeCategories {
    static NSArray<UIContentSizeCategory> *categories;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        categories = @[
            UIContentSizeCategoryExtraSmall,
            UIContentSizeCategorySmall,
            UIContentSizeCategoryMedium,
            UIContentSizeCategoryLarge,
            UIContentSizeCategoryExtraLarge,
            UIContentSizeCategoryExtraExtraLarge,
            UIContentSizeCategoryExtraExtraExtraLarge,
            UIContentSizeCategoryAccessibilityMedium,
            UIContentSizeCategoryAccessibilityLarge,
            UIContentSizeCategoryAccessibilityExtraLarge,
            UIContentSizeCategoryAccessibilityExtraExtraLarge,
            UIContentSizeCategoryAccessibilityExtraExtraExtraLarge,
        ];
    });
    return categories;
}

#pragma mark - checkDefaults / reset

// -[DPUserPreferences checkDefaults] @ 0x100032e20
- (void)checkDefaults {
    if (![self.userDefaults objectForKey:kDPPrefsLastOpenDirectory])
        [self setLastOpenDirectory:@"/"];
    if (![self.userDefaults objectForKey:kDPPrefsPathViewType])
        [self setPathViewType:0];
    if (![self.userDefaults objectForKey:kDPPrefsPathSortingMode])
        [self setPathSortingMode:0];
    if (![self.userDefaults objectForKey:kDPPrefsPathSortingCategory])
        [self setPathSortingCategory:1];
    if (![self.userDefaults objectForKey:kDPPrefsPathSortingDirection])
        [self setPathSortingDirection:1];
    if (![self.userDefaults objectForKey:kDPPrefsSearchMode])
        [self setSearchMode:0];
    if (![self.userDefaults objectForKey:kDPPrefsCacheExpirationLimit])
        [self setCacheExpirationLimit:3600];
    if (![self.userDefaults objectForKey:kDPPrefsInterfaceInteractionType])
        [self setInterfaceInteractionType:2];
    if (![self.userDefaults objectForKey:kDPPrefsContentSize])
        [self setContentSize:nil]; // binary passes -1 (nil) => indexOfObject: returns NSNotFound
    if (![self.userDefaults objectForKey:kDPPrefsFoldersOnTop])
        [self setFoldersOnTop:YES];
    if (![self.userDefaults objectForKey:kDPPrefsShowHiddenFiles])
        [self setShowHiddenFiles:YES];
    if (![self.userDefaults objectForKey:kDPPrefsCatalogCacheIsCompressed])
        [self setCatalogCacheIsCompressed:YES];
    if (![self.userDefaults objectForKey:kDPPrefsKeepRunningInBackground])
        [self setKeepRunningInBackground:NO];
}

// -[DPUserPreferences resetPreferences] @ 0x100033294
- (void)resetPreferences {
    NSArray<NSString *> *keys = @[
        kDPPrefsLastOpenDirectory,
        kDPPrefsPathViewType,
        kDPPrefsPathSortingMode,
        kDPPrefsPathSortingCategory,
        kDPPrefsPathSortingDirection,
        kDPPrefsSearchMode,
        kDPPrefsCacheExpirationLimit,
        kDPPrefsInterfaceInteractionType,
        kDPPrefsContentSize,
        kDPPrefsFoldersOnTop,
        kDPPrefsShowHiddenFiles,
        kDPPrefsCatalogCacheIsCompressed,
    ];
    for (NSString *k in keys) {
        [self.userDefaults removeObjectForKey:k];
    }
    [self checkDefaults];
}

#pragma mark - Accessors

- (NSString *)lastOpenDirectory { return [self.userDefaults objectForKey:kDPPrefsLastOpenDirectory]; }
- (void)setLastOpenDirectory:(NSString *)v { [self.userDefaults setObject:v forKey:kDPPrefsLastOpenDirectory]; }

- (NSString *)lastOpenVersion { return [self.userDefaults objectForKey:kDPPrefsLastOpenVersion]; }
- (void)setLastOpenVersion:(NSString *)v { [self.userDefaults setObject:v forKey:kDPPrefsLastOpenVersion]; }

- (NSInteger)pathViewType { return [self.userDefaults integerForKey:kDPPrefsPathViewType]; }
- (void)setPathViewType:(NSInteger)v { [self.userDefaults setInteger:v forKey:kDPPrefsPathViewType]; }

- (NSInteger)pathSortingMode { return [self.userDefaults integerForKey:kDPPrefsPathSortingMode]; }
- (void)setPathSortingMode:(NSInteger)v { [self.userDefaults setInteger:v forKey:kDPPrefsPathSortingMode]; }

- (NSInteger)pathSortingCategory { return [self.userDefaults integerForKey:kDPPrefsPathSortingCategory]; }
- (void)setPathSortingCategory:(NSInteger)v { [self.userDefaults setInteger:v forKey:kDPPrefsPathSortingCategory]; }

- (NSInteger)pathSortingDirection { return [self.userDefaults integerForKey:kDPPrefsPathSortingDirection]; }
- (void)setPathSortingDirection:(NSInteger)v { [self.userDefaults setInteger:v forKey:kDPPrefsPathSortingDirection]; }

- (NSInteger)searchMode { return [self.userDefaults integerForKey:kDPPrefsSearchMode]; }
- (void)setSearchMode:(NSInteger)v { [self.userDefaults setInteger:v forKey:kDPPrefsSearchMode]; }

- (NSInteger)cacheExpirationLimit { return [self.userDefaults integerForKey:kDPPrefsCacheExpirationLimit]; }
- (void)setCacheExpirationLimit:(NSInteger)v { [self.userDefaults setInteger:v forKey:kDPPrefsCacheExpirationLimit]; }

- (NSInteger)interfaceInteractionType { return [self.userDefaults integerForKey:kDPPrefsInterfaceInteractionType]; }
- (void)setInterfaceInteractionType:(NSInteger)v { [self.userDefaults setInteger:v forKey:kDPPrefsInterfaceInteractionType]; }

// -[DPUserPreferences contentSize] @ 0x10003290c
// Binary returns [array objectAtIndexedSubscript:[defaults integerForKey:...]].
// If integer is NSNotFound (-1) this would crash in -objectAtIndexedSubscript:,
// so we guard and return nil to mean "use system default".
- (UIContentSizeCategory)contentSize {
    NSArray<UIContentSizeCategory> *categories = [[self class] _contentSizeCategories];
    NSInteger idx = [self.userDefaults integerForKey:kDPPrefsContentSize];
    if (idx < 0 || idx >= (NSInteger)categories.count) return nil;
    return categories[idx];
}

// -[DPUserPreferences setContentSize:] @ 0x100032a98
// Binary stores [array indexOfObject:value]. If value is nil or not in the
// table, indexOfObject: returns NSNotFound, which is stored as-is.
- (void)setContentSize:(UIContentSizeCategory)v {
    NSArray<UIContentSizeCategory> *categories = [[self class] _contentSizeCategories];
    NSUInteger idx = v ? [categories indexOfObject:v] : NSNotFound;
    [self.userDefaults setInteger:(NSInteger)idx forKey:kDPPrefsContentSize];
}

- (BOOL)foldersOnTop { return [self.userDefaults boolForKey:kDPPrefsFoldersOnTop]; }
- (void)setFoldersOnTop:(BOOL)v { [self.userDefaults setBool:v forKey:kDPPrefsFoldersOnTop]; }

- (BOOL)showHiddenFiles { return [self.userDefaults boolForKey:kDPPrefsShowHiddenFiles]; }
- (void)setShowHiddenFiles:(BOOL)v { [self.userDefaults setBool:v forKey:kDPPrefsShowHiddenFiles]; }

- (BOOL)catalogCacheIsCompressed { return [self.userDefaults boolForKey:kDPPrefsCatalogCacheIsCompressed]; }
- (void)setCatalogCacheIsCompressed:(BOOL)v { [self.userDefaults setBool:v forKey:kDPPrefsCatalogCacheIsCompressed]; }

- (BOOL)keepRunningInBackground { return [self.userDefaults boolForKey:kDPPrefsKeepRunningInBackground]; }
- (void)setKeepRunningInBackground:(BOOL)v { [self.userDefaults setBool:v forKey:kDPPrefsKeepRunningInBackground]; }

@end
