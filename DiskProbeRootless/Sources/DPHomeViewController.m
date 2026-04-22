#import "DPHomeViewController.h"
#import "DPPathViewController.h"

@implementation DPHomeViewController

+ (instancetype)homeViewController {
    NSDictionary *data = [self defaultData];
    return [DPHomeViewController tableViewControllerWithDataSource:data];
}

+ (NSDictionary *)defaultData {
    NSArray *defaultPaths = @[
        @"/",
        @"/private/var/mobile",
        @"/private/var/mobile/Documents",
        @"/private/var/mobile/Downloads",
        @"/private/var/mobile/Media",
        @"/Applications",
    ];

    NSBundle *bundle = [NSBundle mainBundle];

    // Default Paths section header
    NSMutableArray *defaultSectionRows = [@[
        @{ @"header": [bundle localizedStringForKey:@"Default Paths" value:@"" table:nil] }
    ] mutableCopy];

    NSFileManager *fm = [NSFileManager defaultManager];

    for (NSString *path in defaultPaths) {
        BOOL isDir = NO;
        BOOL exists = [fm fileExistsAtPath:path isDirectory:&isDir];
        if (!exists || !isDir) {
            continue;
        }

        NSString *title;
        if ([path isEqualToString:@"/"]) {
            title = [bundle localizedStringForKey:@"Root" value:@"" table:nil];
        } else {
            title = [[path lastPathComponent] localizedCapitalizedString];
        }

        NSDictionary *row = @{
            @"icon":      @"bookmark.fill",
            @"subtitle":  path,
            @"title":     title,
            @"detail":    @"directory",
            @"cellStyle": @"subtitle",
        };
        [defaultSectionRows addObject:row];
    }

    // Bookmarks section
    NSArray *bookmarkPaths = [[NSUserDefaults standardUserDefaults] objectForKey:@"DPPrefsBookmarkPathList"];

    NSMutableArray *bookmarkSectionRows = [@[
        @{ @"header": [bundle localizedStringForKey:@"Bookmarks" value:@"" table:nil] }
    ] mutableCopy];

    for (NSString *path in bookmarkPaths) {
        BOOL isDir = NO;
        BOOL exists = [fm fileExistsAtPath:path isDirectory:&isDir];
        if (!exists || !isDir) {
            continue;
        }

        NSString *title;
        if ([path isEqualToString:@"/"]) {
            title = [bundle localizedStringForKey:@"Root" value:@"" table:nil];
        } else {
            title = [[path lastPathComponent] localizedCapitalizedString];
        }

        NSDictionary *row = @{
            @"icon":      @"bookmark.fill",
            @"subtitle":  path,
            @"title":     title,
            @"detail":    @"directory",
            @"cellStyle": @"subtitle",
        };
        [bookmarkSectionRows addObject:row];
    }

    NSDictionary *data = @{
        @"title": [bundle localizedStringForKey:@"DiskProbe" value:@"" table:nil],
        @"sections": @[
            @{ @"rows": defaultSectionRows },
            @{ @"rows": bookmarkSectionRows },
        ],
    };
    return data;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self setData:[[self class] defaultData]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];

    NSDictionary *data = [self dataForIndexPath:indexPath];
    NSString *detail = data[@"detail"];
    if ([detail isEqualToString:@"directory"]) {
        NSString *path = data[@"subtitle"];
        DPPathViewController *vc = [DPPathViewController directoryViewControllerWithDirectory:path];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

@end
