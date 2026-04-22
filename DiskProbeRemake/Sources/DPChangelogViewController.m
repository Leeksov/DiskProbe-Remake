#import "DPChangelogViewController.h"
#import "DPUserPreferences.h"

static NSString *const kDPChangelogReleasesURL = @"https://api.github.com/repos/Leeksov/DiskProbe-Remake/releases";

@implementation DPChangelogViewController

+ (instancetype)tableViewControllerWithDataSource:(NSDictionary *)dataSource {
    return [self tableViewControllerWithDataSource:dataSource cellStyle:UITableViewCellStyleSubtitle];
}

+ (instancetype)tableViewControllerWithDataSource:(NSDictionary *)dataSource cellStyle:(UITableViewCellStyle)cellStyle {
    DPChangelogViewController *vc = [DPChangelogViewController new];
    [vc setData:dataSource];
    [vc setCellStyle:cellStyle];
    return vc;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSDictionary *cached = [self loadCachedData];
        if (cached) {
            [self setData:[self dataDictionaryFromReleases:cached[@"releases"]]];
        } else {
            [self setData:@{@"title": @"Changelog",
                            @"sections": @[@{@"header": @{@"title": @"Loading"},
                                             @"rows": @[@{@"title": @"Fetching latest releases...",
                                                          @"cellStyle": @"subtitle"}]}]}];
        }
        [self setCellStyle:UITableViewCellStyleSubtitle];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationController.navigationBar.prefersLargeTitles = NO;

    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];

    UILabel *label = [UILabel new];
    label.font = [UIFont boldSystemFontOfSize:14.0];
    label.textAlignment = NSTextAlignmentCenter;
    label.text = [@"v" stringByAppendingString:version];
    label.textColor = [UIColor darkGrayColor];
    [label sizeToFit];

    [[DPUserPreferences sharedPreferences] setLastOpenVersion:version];

    UIBarButtonItem *rightItem = [[UIBarButtonItem alloc] initWithCustomView:label];
    self.navigationItem.rightBarButtonItem = rightItem;

    UIBarButtonItem *leftItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                              target:self
                                                                              action:@selector(dismiss)];
    self.navigationItem.leftBarButtonItem = leftItem;

    [self fetchReleases];
}

#pragma mark - Cache

- (NSString *)cacheFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachesDir = [paths firstObject];
    return [cachesDir stringByAppendingPathComponent:@"github_changelog.json"];
}

- (NSDictionary *)loadCachedData {
    NSString *path = [self cacheFilePath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    return obj;
}

- (void)saveCachedReleases:(NSArray *)releases {
    NSDictionary *wrapper = @{@"releases": releases ?: @[]};
    NSData *data = [NSJSONSerialization dataWithJSONObject:wrapper options:0 error:nil];
    [data writeToFile:[self cacheFilePath] atomically:YES];
}

#pragma mark - Networking

- (void)fetchReleases {
    NSURL *url = [NSURL URLWithString:kDPChangelogReleasesURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:20.0];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"DiskProbe" forHTTPHeaderField:@"User-Agent"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSArray *releases = nil;
        if (data && !error) {
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([obj isKindOfClass:[NSArray class]]) {
                releases = obj;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (releases) {
                [strongSelf saveCachedReleases:releases];
                [strongSelf setData:[strongSelf dataDictionaryFromReleases:releases]];
            } else {
                NSDictionary *cached = [strongSelf loadCachedData];
                if (cached && [cached[@"releases"] isKindOfClass:[NSArray class]] && [cached[@"releases"] count] > 0) {
                    [strongSelf setData:[strongSelf dataDictionaryFromReleases:cached[@"releases"]]];
                } else {
                    [strongSelf setData:[strongSelf failureDataDictionary]];
                }
            }
        });
    }];
    [task resume];
}

#pragma mark - Data building

- (NSString *)formattedDateFromISOString:(NSString *)iso {
    if (![iso isKindOfClass:[NSString class]] || iso.length < 10) return @"";
    return [iso substringToIndex:10];
}

- (NSDictionary *)dataDictionaryFromReleases:(NSArray *)releases {
    NSMutableArray *sections = [NSMutableArray array];

    if (![releases isKindOfClass:[NSArray class]] || releases.count == 0) {
        return [self failureDataDictionary];
    }

    for (NSDictionary *release in releases) {
        if (![release isKindOfClass:[NSDictionary class]]) continue;

        NSString *tag = [release[@"tag_name"] isKindOfClass:[NSString class]] ? release[@"tag_name"] : @"";
        NSString *name = [release[@"name"] isKindOfClass:[NSString class]] ? release[@"name"] : @"";
        NSString *body = [release[@"body"] isKindOfClass:[NSString class]] ? release[@"body"] : @"";
        NSString *published = [self formattedDateFromISOString:release[@"published_at"]];

        NSString *headerTitle = tag.length ? tag : name;
        if (published.length) {
            headerTitle = [NSString stringWithFormat:@"%@ — %@", headerTitle, published];
        }

        NSMutableArray *rows = [NSMutableArray array];
        NSArray *lines = [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *rawLine in lines) {
            NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (line.length == 0) continue;
            [rows addObject:@{@"title": line, @"cellStyle": @"subtitle"}];
        }

        if (rows.count == 0) {
            NSString *fallback = name.length ? name : @"(no details)";
            [rows addObject:@{@"title": fallback, @"cellStyle": @"subtitle"}];
        }

        [sections addObject:@{@"header": @{@"title": headerTitle ?: @""},
                              @"rows": rows}];
    }

    if (sections.count == 0) {
        return [self failureDataDictionary];
    }

    return @{@"title": @"Changelog", @"sections": sections};
}

- (NSDictionary *)failureDataDictionary {
    return @{@"title": @"Changelog",
             @"sections": @[@{@"header": @{@"title": @"Unavailable"},
                              @"rows": @[@{@"title": @"Failed to fetch changelog",
                                           @"subtitle": @"Tap to retry",
                                           @"cellStyle": @"subtitle",
                                           @"action": @"retryFetch"}]}]};
}

#pragma mark - Retry

- (void)retryFetch {
    [self fetchReleases];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *rowData = [self dataForIndexPath:indexPath];
    NSString *action = rowData[@"action"];
    if ([action isEqualToString:@"retryFetch"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self setData:@{@"title": @"Changelog",
                        @"sections": @[@{@"header": @{@"title": @"Loading"},
                                         @"rows": @[@{@"title": @"Fetching latest releases...",
                                                      @"cellStyle": @"subtitle"}]}]}];
        [self retryFetch];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

@end
