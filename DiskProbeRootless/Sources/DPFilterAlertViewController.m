#import "DPFilterAlertViewController.h"
#import "DPUserPreferences.h"
#import "UIImage+DP.h"
#import "DPSettingsViewController.h"

@implementation DPFilterAlertViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadData];
}

- (void)reloadData {
    NSDictionary *data = [self _fetchDataSource];
    [self setData:data];
}

- (NSDictionary *)_fetchDataSource {
    DPUserPreferences *prefs = [DPUserPreferences sharedPreferences];
    NSUInteger currentViewType = [prefs pathViewType];
    NSUInteger currentDirection = [prefs pathSortingDirection];
    NSUInteger currentCategory = [prefs pathSortingCategory];

    // View type section rows (List/Grid) — [0, 1]
    NSMutableArray *viewTypeRows = [NSMutableArray array];
    [viewTypeRows addObject:@{@"header": @""}];
    NSArray *viewTypeValues = @[@0, @1];
    __weak DPFilterAlertViewController *weakSelf = self;
    [viewTypeValues enumerateObjectsUsingBlock:^(NSNumber *num, NSUInteger idx, BOOL *stop) {
        NSUInteger val = num.unsignedLongValue;
        NSString *title = val ? NSLocalizedString(@"Grid View", nil) : NSLocalizedString(@"List View", nil);
        NSString *accessory = (currentViewType == val) ? @"checkmark" : @"none";
        NSString *iconName = val ? @"rectangle.grid.2x2" : @"rectangle.grid.1x2";
        UIImage *icon = [UIImage dp_systemImageNamed:iconName];
        NSUInteger capturedVal = val;
        void (^block)(void) = ^{
            [[DPUserPreferences sharedPreferences] setPathViewType:capturedVal];
            [[DPUserPreferences sharedPreferences] synchronize];
            [weakSelf reloadData];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationSetViewType" object:nil];
        };
        [viewTypeRows addObject:@{
            @"title": title,
            @"block": block,
            @"accessory": accessory,
            @"iconImage": icon,
            @"iconUsesLabelColor": @YES
        }];
    }];

    // Sort direction section rows — [0=Ascending, 1=Descending]
    NSMutableArray *directionRows = [NSMutableArray array];
    [directionRows addObject:@{@"header": @""}];
    NSArray *directionValues = @[@0, @1];
    [directionValues enumerateObjectsUsingBlock:^(NSNumber *num, NSUInteger idx, BOOL *stop) {
        NSUInteger val = num.unsignedLongValue;
        NSString *title = (val == 1) ? NSLocalizedString(@"Descending", nil) : NSLocalizedString(@"Ascending", nil);
        if (!title) return;
        NSString *accessory = (currentDirection == val) ? @"checkmark" : @"none";
        NSString *iconName = (val & 1) ? @"chevron.down" : @"chevron.up";
        UIImage *icon = [UIImage dp_systemImageNamed:iconName];
        NSUInteger capturedVal = val;
        void (^block)(void) = ^{
            [[DPUserPreferences sharedPreferences] setPathSortingDirection:capturedVal];
            [[DPUserPreferences sharedPreferences] synchronize];
            [weakSelf reloadData];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationSortDataIfNeeded" object:nil];
        };
        [directionRows addObject:@{
            @"title": title,
            @"block": block,
            @"accessory": accessory,
            @"iconImage": icon,
            @"iconUsesLabelColor": @YES
        }];
    }];

    // Sort category section rows — [0=Name, 1=Size, 2=Age]
    NSMutableArray *categoryRows = [NSMutableArray array];
    [categoryRows addObject:@{@"header": @""}];
    NSArray *categoryValues = @[@0, @1, @2];
    [categoryValues enumerateObjectsUsingBlock:^(NSNumber *num, NSUInteger idx, BOOL *stop) {
        NSUInteger val = num.unsignedLongValue;
        NSString *title = nil;
        NSString *iconName = nil;
        if (val == 0) {
            title = NSLocalizedString(@"File Name", nil);
            iconName = @"a.circle";
        } else if (val == 1) {
            title = NSLocalizedString(@"File Size", nil);
            iconName = @"number.circle";
        } else if (val == 2) {
            title = NSLocalizedString(@"File Age", nil);
            iconName = @"clock";
        }
        if (!title) return;
        NSString *accessory = (currentCategory == val) ? @"checkmark" : @"none";
        UIImage *icon = [UIImage dp_systemImageNamed:iconName];
        NSUInteger capturedVal = val;
        void (^block)(void) = ^{
            [[DPUserPreferences sharedPreferences] setPathSortingCategory:capturedVal];
            [[DPUserPreferences sharedPreferences] synchronize];
            [weakSelf reloadData];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationSortDataIfNeeded" object:nil];
        };
        [categoryRows addObject:@{
            @"title": title,
            @"block": block,
            @"accessory": accessory,
            @"iconImage": icon,
            @"iconUsesLabelColor": @YES
        }];
    }];

    // Settings toggles section
    void (^foldersBlock)(void) = ^{
        [[DPUserPreferences sharedPreferences] synchronize];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationSortData" object:nil];
    };
    void (^hiddenBlock)(void) = ^{
        [[DPUserPreferences sharedPreferences] synchronize];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationRefreshData" object:nil];
    };

    NSArray *settingsRows = @[
        @{
            @"title": NSLocalizedString(@"Folders Above Files", nil),
            @"control": @"switch",
            @"prefsKey": @"DPPrefsFoldersOnTop",
            @"block": foldersBlock
        },
        @{
            @"title": NSLocalizedString(@"Show Hidden Files", nil),
            @"control": @"switch",
            @"prefsKey": @"DPPrefsShowHiddenFiles",
            @"block": hiddenBlock
        }
    ];

    // Open Settings section
    void (^openSettingsBlock)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            UIApplication *app = [UIApplication sharedApplication];
            id delegate = [app delegate];
            UIWindow *window = [delegate window];
            UIViewController *root = window.rootViewController;
            DPSettingsViewController *settings = [DPSettingsViewController new];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
            [root presentViewController:nav animated:YES completion:nil];
        });
    };

    NSDictionary *openSettingsHeaderRow = @{@"header": @""};
    NSDictionary *openSettingsRow = @{
        @"title": NSLocalizedString(@"Open Settings", nil),
        @"dismissBefore": @YES,
        @"accessory": @"disclosureIndicator",
        @"block": openSettingsBlock,
        @"iconImage": [UIImage dp_systemImageNamed:@"gear"],
        @"iconUsesLabelColor": @YES
    };

    NSArray *sections = @[
        @{@"rows": settingsRows},
        @{@"rows": viewTypeRows},
        @{@"rows": directionRows},
        @{@"rows": categoryRows},
        @{@"rows": @[openSettingsHeaderRow, openSettingsRow]}
    ];

    return @{
        @"title": @"Info",
        @"sections": sections
    };
}

@end
