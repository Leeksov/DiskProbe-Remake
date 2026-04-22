#import "DPChangelogViewController.h"
#import "DPUserPreferences.h"

static NSString *const kDPChangelogReleasesURL = @"https://api.github.com/repos/Leeksov/DiskProbe-Remake/releases";

typedef NS_ENUM(NSInteger, DPChangelogLineType) {
    DPChangelogLineTypePlain = 0,
    DPChangelogLineTypeH2,
    DPChangelogLineTypeH3,
    DPChangelogLineTypeH4,
    DPChangelogLineTypeBullet,
    DPChangelogLineTypeEmpty,
    DPChangelogLineTypeRetry,
    DPChangelogLineTypeLoading,
};

@interface DPChangelogViewController ()
// Each section: @{ @"tag": NSString, @"name": NSString, @"date": NSString, @"lines": NSArray<NSDictionary*> }
// Each line:   @{ @"type": NSNumber (DPChangelogLineType), @"text": NSString }
@property (nonatomic, strong) NSArray<NSDictionary *> *releaseSections;
@property (nonatomic, assign) BOOL failed;
@property (nonatomic, assign) BOOL loading;
@end

@implementation DPChangelogViewController

+ (instancetype)tableViewControllerWithDataSource:(NSDictionary *)dataSource {
    return [self tableViewControllerWithDataSource:dataSource cellStyle:UITableViewCellStyleDefault];
}

+ (instancetype)tableViewControllerWithDataSource:(NSDictionary *)dataSource cellStyle:(UITableViewCellStyle)cellStyle {
    DPChangelogViewController *vc = [DPChangelogViewController new];
    return vc;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setData:@{@"title": @"Changelog", @"sections": @[]}];
        [self setCellStyle:UITableViewCellStyleDefault];

        NSDictionary *cached = [self loadCachedData];
        if (cached && [cached[@"releases"] isKindOfClass:[NSArray class]] && [cached[@"releases"] count] > 0) {
            self.releaseSections = [self buildSectionsFromReleases:cached[@"releases"]];
            self.loading = NO;
        } else {
            self.loading = YES;
            self.releaseSections = @[];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Changelog";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    [[DPUserPreferences sharedPreferences] setLastOpenVersion:version];

    self.navigationItem.rightBarButtonItem = nil;
    self.navigationItem.leftBarButtonItem = nil;

    self.tableView.estimatedRowHeight = 44.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 44.0;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;

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
            strongSelf.loading = NO;
            if (releases && releases.count > 0) {
                [strongSelf saveCachedReleases:releases];
                strongSelf.failed = NO;
                strongSelf.releaseSections = [strongSelf buildSectionsFromReleases:releases];
            } else {
                NSDictionary *cached = [strongSelf loadCachedData];
                if (cached && [cached[@"releases"] isKindOfClass:[NSArray class]] && [cached[@"releases"] count] > 0) {
                    strongSelf.failed = NO;
                    strongSelf.releaseSections = [strongSelf buildSectionsFromReleases:cached[@"releases"]];
                } else {
                    strongSelf.failed = YES;
                    strongSelf.releaseSections = @[];
                }
            }
            [strongSelf.tableView reloadData];
        });
    }];
    [task resume];
}

#pragma mark - Parsing

- (NSString *)formattedDateFromISOString:(NSString *)iso {
    if (![iso isKindOfClass:[NSString class]] || iso.length < 10) return @"";
    return [iso substringToIndex:10];
}

- (NSArray<NSDictionary *> *)buildSectionsFromReleases:(NSArray *)releases {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *release in releases) {
        if (![release isKindOfClass:[NSDictionary class]]) continue;
        NSString *tag = [release[@"tag_name"] isKindOfClass:[NSString class]] ? release[@"tag_name"] : @"";
        NSString *name = [release[@"name"] isKindOfClass:[NSString class]] ? release[@"name"] : @"";
        NSString *body = [release[@"body"] isKindOfClass:[NSString class]] ? release[@"body"] : @"";
        NSString *date = [self formattedDateFromISOString:release[@"published_at"]];

        NSArray *rawLines = [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSMutableArray *lines = [NSMutableArray array];
        for (NSString *rawLine in rawLines) {
            NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (line.length == 0) continue;
            DPChangelogLineType type = DPChangelogLineTypePlain;
            NSString *text = line;
            if ([line hasPrefix:@"#### "]) { type = DPChangelogLineTypeH4; text = [line substringFromIndex:5]; }
            else if ([line hasPrefix:@"### "]) { type = DPChangelogLineTypeH3; text = [line substringFromIndex:4]; }
            else if ([line hasPrefix:@"## "]) { type = DPChangelogLineTypeH2; text = [line substringFromIndex:3]; }
            else if ([line hasPrefix:@"# "]) { type = DPChangelogLineTypeH2; text = [line substringFromIndex:2]; }
            else if ([line hasPrefix:@"- "]) { type = DPChangelogLineTypeBullet; text = [line substringFromIndex:2]; }
            else if ([line hasPrefix:@"* "]) { type = DPChangelogLineTypeBullet; text = [line substringFromIndex:2]; }
            [lines addObject:@{@"type": @(type), @"text": text}];
        }
        if (lines.count == 0) {
            [lines addObject:@{@"type": @(DPChangelogLineTypePlain), @"text": name.length ? name : @"(no details)"}];
        }

        [out addObject:@{@"tag": tag ?: @"",
                         @"name": name ?: @"",
                         @"date": date ?: @"",
                         @"lines": lines}];
    }
    return out;
}

#pragma mark - Inline markdown → NSAttributedString

- (UIFont *)baseBodyFont {
    return [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
}

- (UIFont *)boldVariantOfFont:(UIFont *)font {
    UIFontDescriptor *desc = [font.fontDescriptor fontDescriptorWithSymbolicTraits:
                              font.fontDescriptor.symbolicTraits | UIFontDescriptorTraitBold];
    return desc ? [UIFont fontWithDescriptor:desc size:font.pointSize] : font;
}

- (UIFont *)italicVariantOfFont:(UIFont *)font {
    UIFontDescriptor *desc = [font.fontDescriptor fontDescriptorWithSymbolicTraits:
                              font.fontDescriptor.symbolicTraits | UIFontDescriptorTraitItalic];
    return desc ? [UIFont fontWithDescriptor:desc size:font.pointSize] : font;
}

- (NSAttributedString *)attributedStringFromInlineMarkdown:(NSString *)src font:(UIFont *)baseFont color:(UIColor *)color {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    if (src.length == 0) return out;

    NSUInteger i = 0;
    NSUInteger len = src.length;
    UIFont *boldFont = [self boldVariantOfFont:baseFont];
    UIFont *italicFont = [self italicVariantOfFont:baseFont];
    UIFont *codeFont = [UIFont monospacedSystemFontOfSize:baseFont.pointSize weight:UIFontWeightRegular];
    UIColor *codeBg = [UIColor colorWithWhite:0.5 alpha:0.18];

    NSMutableString *plainRun = [NSMutableString string];
    void (^flushPlain)(void) = ^{
        if (plainRun.length) {
            NSDictionary *attrs = @{NSFontAttributeName: baseFont,
                                    NSForegroundColorAttributeName: color};
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:[plainRun copy] attributes:attrs]];
            [plainRun setString:@""];
        }
    };

    while (i < len) {
        unichar c = [src characterAtIndex:i];

        // `code`
        if (c == '`') {
            NSRange end = [src rangeOfString:@"`" options:0 range:NSMakeRange(i + 1, len - (i + 1))];
            if (end.location != NSNotFound) {
                flushPlain();
                NSString *code = [src substringWithRange:NSMakeRange(i + 1, end.location - (i + 1))];
                NSDictionary *attrs = @{NSFontAttributeName: codeFont,
                                        NSForegroundColorAttributeName: color,
                                        NSBackgroundColorAttributeName: codeBg};
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:code attributes:attrs]];
                i = end.location + 1;
                continue;
            }
        }

        // **bold**
        if (c == '*' && i + 1 < len && [src characterAtIndex:i + 1] == '*') {
            NSRange end = [src rangeOfString:@"**" options:0 range:NSMakeRange(i + 2, len - (i + 2))];
            if (end.location != NSNotFound) {
                flushPlain();
                NSString *inner = [src substringWithRange:NSMakeRange(i + 2, end.location - (i + 2))];
                // Recurse for nested inline (e.g. italic inside bold handled minimally — just bold)
                NSDictionary *attrs = @{NSFontAttributeName: boldFont,
                                        NSForegroundColorAttributeName: color};
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:inner attributes:attrs]];
                i = end.location + 2;
                continue;
            }
        }

        // *italic*  (single asterisk, not part of **)
        if (c == '*') {
            NSRange searchRange = NSMakeRange(i + 1, len - (i + 1));
            NSRange end = [src rangeOfString:@"*" options:0 range:searchRange];
            if (end.location != NSNotFound && end.location > i + 1) {
                // ensure not the start of **
                BOOL isDouble = (end.location + 1 < len && [src characterAtIndex:end.location + 1] == '*');
                if (!isDouble) {
                    flushPlain();
                    NSString *inner = [src substringWithRange:NSMakeRange(i + 1, end.location - (i + 1))];
                    NSDictionary *attrs = @{NSFontAttributeName: italicFont,
                                            NSForegroundColorAttributeName: color};
                    [out appendAttributedString:[[NSAttributedString alloc] initWithString:inner attributes:attrs]];
                    i = end.location + 1;
                    continue;
                }
            }
        }

        // _italic_
        if (c == '_') {
            NSRange searchRange = NSMakeRange(i + 1, len - (i + 1));
            NSRange end = [src rangeOfString:@"_" options:0 range:searchRange];
            if (end.location != NSNotFound && end.location > i + 1) {
                flushPlain();
                NSString *inner = [src substringWithRange:NSMakeRange(i + 1, end.location - (i + 1))];
                NSDictionary *attrs = @{NSFontAttributeName: italicFont,
                                        NSForegroundColorAttributeName: color};
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:inner attributes:attrs]];
                i = end.location + 1;
                continue;
            }
        }

        [plainRun appendFormat:@"%C", c];
        i++;
    }
    flushPlain();
    return out;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.loading) return 1;
    if (self.failed) return 1;
    return (NSInteger)self.releaseSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.loading) return 1;
    if (self.failed) return 1;
    if (section >= (NSInteger)self.releaseSections.count) return 0;
    NSDictionary *s = self.releaseSections[section];
    NSArray *lines = s[@"lines"];
    return (NSInteger)lines.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.loading) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"dp_cl_loading"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"dp_cl_loading"];
        cell.textLabel.text = @"Fetching latest releases…";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        cell.textLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    if (self.failed) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"dp_cl_failed"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"dp_cl_failed"];
        cell.textLabel.text = @"Failed to fetch changelog";
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.text = @"Tap to retry";
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    NSDictionary *s = self.releaseSections[indexPath.section];
    NSArray *lines = s[@"lines"];
    NSDictionary *line = lines[indexPath.row];
    DPChangelogLineType type = (DPChangelogLineType)[line[@"type"] integerValue];
    NSString *text = line[@"text"] ?: @"";

    NSString *reuseId = [NSString stringWithFormat:@"dp_cl_t%ld", (long)type];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseId];

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.indentationLevel = 0;
    cell.indentationWidth = 10.0;
    cell.separatorInset = UIEdgeInsetsMake(0, 16, 0, 0);

    UIFont *baseFont = [self baseBodyFont];
    UIColor *color = [UIColor labelColor];

    switch (type) {
        case DPChangelogLineTypeH2: {
            UIFont *f = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
            cell.textLabel.attributedText = [self attributedStringFromInlineMarkdown:text font:f color:color];
            cell.backgroundColor = [UIColor tertiarySystemGroupedBackgroundColor];
            break;
        }
        case DPChangelogLineTypeH3: {
            UIFont *f = [UIFont systemFontOfSize:19.0 weight:UIFontWeightSemibold];
            cell.textLabel.attributedText = [self attributedStringFromInlineMarkdown:text font:f color:color];
            cell.backgroundColor = [UIColor tertiarySystemGroupedBackgroundColor];
            break;
        }
        case DPChangelogLineTypeH4: {
            UIFont *f = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
            cell.textLabel.attributedText = [self attributedStringFromInlineMarkdown:text font:f color:color];
            break;
        }
        case DPChangelogLineTypeBullet: {
            NSMutableAttributedString *combined = [[NSMutableAttributedString alloc] init];
            NSDictionary *bulletAttrs = @{NSFontAttributeName: baseFont,
                                          NSForegroundColorAttributeName: [UIColor secondaryLabelColor]};
            [combined appendAttributedString:[[NSAttributedString alloc] initWithString:@"•  " attributes:bulletAttrs]];
            [combined appendAttributedString:[self attributedStringFromInlineMarkdown:text font:baseFont color:color]];
            NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
            ps.firstLineHeadIndent = 0;
            ps.headIndent = 18.0;
            ps.paragraphSpacing = 2.0;
            [combined addAttribute:NSParagraphStyleAttributeName value:ps range:NSMakeRange(0, combined.length)];
            cell.textLabel.attributedText = combined;
            cell.separatorInset = UIEdgeInsetsMake(0, 32, 0, 0);
            break;
        }
        case DPChangelogLineTypePlain:
        default: {
            cell.textLabel.attributedText = [self attributedStringFromInlineMarkdown:text font:baseFont color:color];
            break;
        }
    }

    return cell;
}

#pragma mark - Section headers

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (self.loading || self.failed) return nil;
    if (section >= (NSInteger)self.releaseSections.count) return nil;
    NSDictionary *s = self.releaseSections[section];
    NSString *tag = s[@"tag"] ?: @"";
    NSString *name = s[@"name"] ?: @"";
    NSString *date = s[@"date"] ?: @"";

    UIView *container = [[UIView alloc] init];
    container.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.numberOfLines = 0;
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];
    if (tag.length) {
        [attr appendAttributedString:[[NSAttributedString alloc] initWithString:tag
                                                                     attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold],
                                                                                  NSForegroundColorAttributeName: [UIColor labelColor]}]];
    }
    if (name.length && ![name isEqualToString:tag]) {
        if (attr.length) {
            [attr appendAttributedString:[[NSAttributedString alloc] initWithString:@"  —  "
                                                                         attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular],
                                                                                      NSForegroundColorAttributeName: [UIColor secondaryLabelColor]}]];
        }
        [attr appendAttributedString:[[NSAttributedString alloc] initWithString:name
                                                                     attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium],
                                                                                  NSForegroundColorAttributeName: [UIColor secondaryLabelColor]}]];
    }
    title.attributedText = attr;
    [container addSubview:title];

    UILabel *dateLabel = [[UILabel alloc] init];
    dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    dateLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    dateLabel.textColor = [UIColor tertiaryLabelColor];
    dateLabel.text = date;
    dateLabel.textAlignment = NSTextAlignmentRight;
    [dateLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [dateLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [container addSubview:dateLabel];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:container.layoutMarginsGuide.leadingAnchor],
        [title.topAnchor constraintEqualToAnchor:container.topAnchor constant:14.0],
        [title.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8.0],
        [dateLabel.trailingAnchor constraintEqualToAnchor:container.layoutMarginsGuide.trailingAnchor],
        [dateLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:8.0],
        [dateLabel.firstBaselineAnchor constraintEqualToAnchor:title.firstBaselineAnchor],
    ]];
    return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (self.loading || self.failed) return 0.01;
    return UITableViewAutomaticDimension;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return nil;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.failed) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        self.failed = NO;
        self.loading = YES;
        [tableView reloadData];
        [self fetchReleases];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.failed) return indexPath;
    return nil;
}

@end
