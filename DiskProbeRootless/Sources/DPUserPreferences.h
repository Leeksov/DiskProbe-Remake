#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface DPUserPreferences : NSObject

@property (nonatomic, strong, readonly) NSUserDefaults *userDefaults;

+ (instancetype)sharedPreferences;
- (instancetype)initWithUserDefaults:(NSUserDefaults *)defaults;
- (void)synchronize;

// Directory navigation
@property (nonatomic, copy) NSString *lastOpenDirectory;
@property (nonatomic, copy) NSString *lastOpenVersion;

// View settings
@property (nonatomic, assign) NSInteger pathViewType;          // 0=table, 1=collection
@property (nonatomic, assign) NSInteger pathSortingMode;       // 0=name, 1=size, 2=date, 3=ext
@property (nonatomic, assign) NSInteger pathSortingCategory;   // 0=files, 1=folders+files
@property (nonatomic, assign) NSInteger pathSortingDirection;  // 0=asc, 1=desc
@property (nonatomic, assign) NSInteger searchMode;            // 0=exact, 1=wildcard
@property (nonatomic, assign) NSInteger cacheExpirationLimit;  // seconds, default 3600
@property (nonatomic, assign) NSInteger interfaceInteractionType; // 0=none, 1=peek&pop, 2=context menu
// contentSize is stored as an index into a 12-element UIContentSizeCategory
// array (ExtraSmall..AccessibilityExtraExtraExtraLarge). A stored value of
// NSNotFound / -1 means "system default" — the getter returns nil in that case.
@property (nonatomic, copy) UIContentSizeCategory contentSize;
@property (nonatomic, assign) BOOL foldersOnTop;
@property (nonatomic, assign) BOOL showHiddenFiles;
@property (nonatomic, assign) BOOL catalogCacheIsCompressed;
@property (nonatomic, assign) BOOL keepRunningInBackground;

- (void)checkDefaults;
- (void)resetPreferences;

@end
