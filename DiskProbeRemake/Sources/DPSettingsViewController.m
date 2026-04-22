#import "DPSettingsViewController.h"
#import "DPUserPreferences.h"
#import "DPCatalog.h"
#import "DPHelper.h"
#import "DPChangelogViewController.h"
#import "UIColor+DP.h"
#import <MessageUI/MessageUI.h>
#import <SafariServices/SafariServices.h>

// Sections (faithful to Settings.plist from the original binary, minus DRM/Debug groups)
typedef NS_ENUM(NSInteger, DPSettingsSection) {
    DPSettingsSectionCache = 0,
    DPSettingsSectionGeneral,
    DPSettingsSectionProduct,
    DPSettingsSectionContact,
    DPSettingsSectionCredits,
    DPSettingsSectionReset,
    DPSettingsSectionCount,
};

// Rows in Cache section
typedef NS_ENUM(NSInteger, DPCacheRow) {
    DPCacheRowCompress = 0,
    DPCacheRowExpiration,
    DPCacheRowClear,
    DPCacheRowCount,
};

// Rows in General section
typedef NS_ENUM(NSInteger, DPGeneralRow) {
    DPGeneralRowFoldersOnTop = 0,
    DPGeneralRowShowHidden,
    DPGeneralRowKeepRunningInBackground,
    DPGeneralRowFontSize,
    DPGeneralRowInteractionType,
    DPGeneralRowCount,
};

// Rows in Product section (DRM rows removed: registration-specifier, purchase-specifier)
typedef NS_ENUM(NSInteger, DPProductRow) {
    DPProductRowChangelog = 0,
    DPProductRowCount,
};

// Rows in Contact section (paypal/Donate removed, Twitter moved to Credits)
typedef NS_ENUM(NSInteger, DPContactRow) {
    DPContactRowEmail = 0,
    DPContactRowCount,
};

// Rows in Credits section
typedef NS_ENUM(NSInteger, DPCreditsRow) {
    DPCreditsRowAuthor = 0,
    DPCreditsRowCount,
};

@interface DPSettingsViewController () <MFMailComposeViewControllerDelegate, SFSafariViewControllerDelegate>
@end

@implementation DPSettingsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSLocalizedString(@"Settings", nil);
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(dismiss)];

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"subtitleCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"switchCell"];

    self.tableView.tableHeaderView = [self headerView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void)dismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Header

// Mirrors -[DPSettingsViewController headerView] from IDA: stack view with
// 20pt spacer, 90x90 rounded app icon, app name label, "by: Leeksov".
- (UIView *)headerView {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.alignment = UIStackViewAlignmentCenter;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.distribution = UIStackViewDistributionEqualSpacing;
    stack.spacing = 8.0;

    UIImageView *icon = [[UIImageView alloc] init];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.image = [UIImage imageNamed:@"AppIconRounded"];
    icon.layer.cornerRadius = 23.0;
    icon.clipsToBounds = YES;
    if (@available(iOS 13.0, *)) {
        icon.layer.cornerCurve = kCACornerCurveContinuous;
    }

    UILabel *name = [UILabel new];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    name.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
    name.textAlignment = NSTextAlignmentCenter;
    name.text = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] ?: @"DiskProbe";
    name.textColor = [UIColor dp_labelColor];

    UILabel *by = [UILabel new];
    by.translatesAutoresizingMaskIntoConstraints = NO;
    by.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    by.textAlignment = NSTextAlignmentCenter;
    by.text = NSLocalizedString(@"by: Leeksov", nil);
    by.textColor = [UIColor dp_secondaryLabelColor];

    UIView *spacer = [UIView new];
    [stack addArrangedSubview:spacer];
    [stack addArrangedSubview:icon];
    [stack addArrangedSubview:name];
    [stack addArrangedSubview:by];

    [[icon.widthAnchor constraintEqualToConstant:90.0] setActive:YES];
    [[icon.heightAnchor constraintEqualToConstant:90.0] setActive:YES];
    [[spacer.heightAnchor constraintEqualToConstant:20.0] setActive:YES];

    CGSize fit = [stack systemLayoutSizeFittingSize:CGSizeMake(CGRectGetWidth(self.view.bounds), 130.0)];
    stack.frame = CGRectMake(0, 0, fit.width, fit.height);
    return stack;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return DPSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((DPSettingsSection)section) {
        case DPSettingsSectionCache:   return DPCacheRowCount;
        case DPSettingsSectionGeneral: return DPGeneralRowCount;
        case DPSettingsSectionProduct: return DPProductRowCount;
        case DPSettingsSectionContact: return DPContactRowCount;
        case DPSettingsSectionCredits: return DPCreditsRowCount;
        case DPSettingsSectionReset:   return 1;
        case DPSettingsSectionCount:   break;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ((DPSettingsSection)section) {
        case DPSettingsSectionCache:   return NSLocalizedString(@"Cache", nil);
        case DPSettingsSectionGeneral: return NSLocalizedString(@"General", nil);
        case DPSettingsSectionProduct: return NSLocalizedString(@"Product", nil);
        case DPSettingsSectionContact: return NSLocalizedString(@"Contact Me", nil);
        case DPSettingsSectionCredits: return NSLocalizedString(@"Credits", nil);
        case DPSettingsSectionReset:   return nil;
        case DPSettingsSectionCount:   break;
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == DPSettingsSectionCache) {
        NSUInteger count = [DPCatalog sharedCatalog].totalScannedItems;
        NSString *countStr = [NSNumberFormatter localizedStringFromNumber:@(count)
                                                              numberStyle:NSNumberFormatterDecimalStyle];
        return [NSString stringWithFormat:NSLocalizedString(@"%@ files and directories in catalog cache.", nil), countStr];
    }
    if (section == DPSettingsSectionReset) {
        return @"Leeksov © 2018 - 2026";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DPUserPreferences *prefs = [DPUserPreferences sharedPreferences];

    switch ((DPSettingsSection)indexPath.section) {
        case DPSettingsSectionCache: {
            switch ((DPCacheRow)indexPath.row) {
                case DPCacheRowCompress:
                    // PSSwitchCell, key=DPPrefsCatalogCacheIsCompressed, label="Compress Cache File"
                    return [self _switchCellForTitle:NSLocalizedString(@"Compress Cache File", nil)
                                               value:prefs.catalogCacheIsCompressed
                                              action:@selector(_toggleCacheCompression:)];
                case DPCacheRowExpiration: {
                    // PSLinkListCell, key=DPPrefsCacheExpirationLimit, label="Cache Experation Limit"
                    UITableViewCell *cell = [self _valueCellForIdentifier:@"cell" indexPath:indexPath];
                    cell.textLabel.text = NSLocalizedString(@"Cache Experation Limit", nil);
                    cell.detailTextLabel.text = [DPHelper displayStringForTimeInterval:prefs.cacheExpirationLimit];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    return cell;
                }
                case DPCacheRowClear: {
                    // PSButtonCell action=clearCache, id=clearCacheNow, subtitle=catalog size
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"subtitleCell"
                                                                            forIndexPath:indexPath];
                    cell.textLabel.text = NSLocalizedString(@"Clear Catalog Cache", nil);
                    cell.detailTextLabel.text = [DPCatalog catalogSize];
                    cell.detailTextLabel.textColor = [UIColor dp_secondaryLabelColor];
                    return cell;
                }
                case DPCacheRowCount: break;
            }
            break;
        }

        case DPSettingsSectionGeneral: {
            switch ((DPGeneralRow)indexPath.row) {
                case DPGeneralRowFoldersOnTop:
                    // PSSwitchCell, key=DPPrefsFoldersOnTop, label="Folders Above Files"
                    return [self _switchCellForTitle:NSLocalizedString(@"Folders Above Files", nil)
                                               value:prefs.foldersOnTop
                                              action:@selector(_toggleFoldersOnTop:)];
                case DPGeneralRowShowHidden:
                    // PSSwitchCell, key=DPPrefsShowHiddenFiles, label="Show Hidden Items"
                    return [self _switchCellForTitle:NSLocalizedString(@"Show Hidden Items", nil)
                                               value:prefs.showHiddenFiles
                                              action:@selector(_toggleShowHiddenFiles:)];
                case DPGeneralRowKeepRunningInBackground:
                    return [self _switchCellForTitle:NSLocalizedString(@"Keep Running in Background", nil)
                                               value:prefs.keepRunningInBackground
                                              action:@selector(_toggleKeepRunningInBackground:)];
                case DPGeneralRowFontSize: {
                    // PSLinkListCell, key=DPPrefsContentSize, label="Font Size"
                    UITableViewCell *cell = [self _valueCellForIdentifier:@"cell" indexPath:indexPath];
                    cell.textLabel.text = NSLocalizedString(@"Font Size", nil);
                    NSArray *titles = [self contentSizeTitles];
                    NSArray *values = [self contentSizeValues];
                    UIContentSizeCategory current = prefs.contentSize;
                    NSUInteger idx = current ? [values indexOfObject:current] : NSNotFound;
                    cell.detailTextLabel.text = (idx != NSNotFound && idx < titles.count)
                        ? titles[idx]
                        : NSLocalizedString(@"System Default", nil);
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    return cell;
                }
                case DPGeneralRowInteractionType: {
                    // PSLinkListCell, key=DPPrefsInterfaceInteractionType, label="Interaction Type"
                    UITableViewCell *cell = [self _valueCellForIdentifier:@"cell" indexPath:indexPath];
                    cell.textLabel.text = NSLocalizedString(@"Interaction Type", nil);
                    NSArray *names = [self interfaceInteractionTypeNames];
                    NSArray *values = [self interfaceInteractionTypeValues];
                    NSUInteger idx = [values indexOfObject:@((int)prefs.interfaceInteractionType)];
                    cell.detailTextLabel.text = (idx != NSNotFound && idx < names.count) ? names[idx] : @"";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    return cell;
                }
                case DPGeneralRowCount: break;
            }
            break;
        }

        case DPSettingsSectionProduct: {
            // Only Changelog remains (registration-specifier and purchase-specifier omitted - DRM)
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
            cell.textLabel.text = NSLocalizedString(@"Changelog", nil);
            if (@available(iOS 13.0, *)) {
                cell.imageView.image = [UIImage systemImageNamed:@"safari"];
            }
            return cell;
        }

        case DPSettingsSectionContact: {
            // Paypal/Donate row omitted - donation link. Twitter moved to Credits.
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
            switch ((DPContactRow)indexPath.row) {
                case DPContactRowEmail:
                    cell.textLabel.text = NSLocalizedString(@"Email Support", nil);
                    break;
                case DPContactRowCount: break;
            }
            return cell;
        }

        case DPSettingsSectionCredits: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"subtitleCell"
                                                                    forIndexPath:indexPath];
            switch ((DPCreditsRow)indexPath.row) {
                case DPCreditsRowAuthor:
                    cell.textLabel.text = @"CreatureSurvive";
                    cell.detailTextLabel.text = NSLocalizedString(@"Original DiskProbe author", nil);
                    cell.detailTextLabel.textColor = [UIColor dp_secondaryLabelColor];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case DPCreditsRowCount: break;
            }
            return cell;
        }

        case DPSettingsSectionReset: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
            cell.textLabel.text = NSLocalizedString(@"Reset Preferences", nil);
            cell.textLabel.textColor = [UIColor systemRedColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            return cell;
        }

        case DPSettingsSectionCount: break;
    }

    return [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch ((DPSettingsSection)indexPath.section) {
        case DPSettingsSectionCache:
            if (indexPath.row == DPCacheRowExpiration) {
                [self _presentListPickerWithTitle:NSLocalizedString(@"Cache Experation Limit", nil)
                                           titles:[self cacheExpirationTitles]
                                           values:[self cacheExpirationValues]
                                          keyPath:@"cacheExpirationLimit"];
            } else if (indexPath.row == DPCacheRowClear) {
                [self clearCache];
            }
            break;

        case DPSettingsSectionGeneral:
            if (indexPath.row == DPGeneralRowFontSize) {
                [self _presentListPickerWithTitle:NSLocalizedString(@"Font Size", nil)
                                           titles:[self contentSizeTitles]
                                           values:[self contentSizeValues]
                                          keyPath:@"contentSize"];
            } else if (indexPath.row == DPGeneralRowInteractionType) {
                [self _presentListPickerWithTitle:NSLocalizedString(@"Interaction Type", nil)
                                           titles:[self interfaceInteractionTypeNames]
                                           values:[self interfaceInteractionTypeValues]
                                          keyPath:@"interfaceInteractionType"];
            }
            break;

        case DPSettingsSectionProduct:
            if (indexPath.row == DPProductRowChangelog) {
                [self openChangelog];
            }
            // registration / purchase rows intentionally removed (DRM).
            break;

        case DPSettingsSectionContact:
            if (indexPath.row == DPContactRowEmail) {
                [self contact];
            }
            // paypal / Donate row intentionally removed. Twitter moved to Credits.
            break;

        case DPSettingsSectionCredits:
            if (indexPath.row == DPCreditsRowAuthor) {
                [self twitter];
            }
            break;

        case DPSettingsSectionReset:
            [self resetPreferences];
            break;

        case DPSettingsSectionCount: break;
    }
}

#pragma mark - Switch / cell helpers

- (UITableViewCell *)_switchCellForTitle:(NSString *)title value:(BOOL)value action:(SEL)action {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                   reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = value;
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (UITableViewCell *)_valueCellForIdentifier:(NSString *)identifier indexPath:(NSIndexPath *)indexPath {
    // Value1-style cell (title + right-side detail).
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                   reuseIdentifier:identifier];
    return cell;
}

#pragma mark - Toggles (PSSwitchCell handlers)

- (void)_toggleShowHiddenFiles:(UISwitch *)sw {
    [DPUserPreferences sharedPreferences].showHiddenFiles = sw.isOn;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationRefreshData" object:nil];
}

- (void)_toggleFoldersOnTop:(UISwitch *)sw {
    [DPUserPreferences sharedPreferences].foldersOnTop = sw.isOn;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DPNotificationSortData" object:nil];
}

- (void)_toggleKeepRunningInBackground:(UISwitch *)sw {
    [DPUserPreferences sharedPreferences].keepRunningInBackground = sw.isOn;
}

- (void)_toggleCacheCompression:(UISwitch *)sw {
    [DPUserPreferences sharedPreferences].catalogCacheIsCompressed = sw.isOn;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [DPCatalog refetchCatalogs];
    });
}

#pragma mark - List picker (stand-in for PSListItemsController)

- (void)_presentListPickerWithTitle:(NSString *)title
                             titles:(NSArray *)titles
                             values:(NSArray *)values
                            keyPath:(NSString *)keyPath {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    DPUserPreferences *prefs = [DPUserPreferences sharedPreferences];
    for (NSUInteger i = 0; i < MIN(titles.count, values.count); i++) {
        NSNumber *v = values[i];
        [ac addAction:[UIAlertAction actionWithTitle:titles[i]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction * _Nonnull action) {
            [prefs setValue:v forKey:keyPath];
            [self.tableView reloadData];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    ac.popoverPresentationController.sourceView = self.view;
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Actions

// -[DPSettingsViewController clearCache]
- (void)clearCache {
    [[NSFileManager defaultManager] removeItemAtPath:[DPCatalog catalogPath] error:nil];
    [DPCatalog refetchCatalogs];
    [self.tableView reloadData];
}

// -[DPSettingsViewController contact] - original used mailto:support@creaturecoding.com,
// per user instruction the recipient is changed to leeksov@gmail.com.
- (void)contact {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    if ([MFMailComposeViewController canSendMail]) {
        MFMailComposeViewController *vc = [[MFMailComposeViewController alloc] init];
        vc.mailComposeDelegate = self;
        [vc setToRecipients:@[@"leeksov@gmail.com"]];
        [vc setSubject:[NSString stringWithFormat:@"DiskProbe v%@", version]];
        [self presentViewController:vc animated:YES completion:nil];
    } else {
        NSString *mailto = [NSString stringWithFormat:
            @"mailto:leeksov@gmail.com?subject=DiskProbe%%20v%@", version];
        NSURL *url = [NSURL URLWithString:mailto];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }
}

// -[DPSettingsViewController twitter] - external URL, not DRM.
- (void)twitter {
    [self openURLInBrowser:@"https://mobile.twitter.com/creaturesurvive"];
}

// -[DPSettingsViewController paypal]       - OMITTED (donation URL).
// -[DPSettingsViewController registration] - OMITTED (DRM: creaturecoding.com/?page=registration).
// -[DPSettingsViewController purchase]     - OMITTED (DRM: creaturecoding.com checkout URL).

// -[DPSettingsViewController openURLInBrowser:] - preserved for twitter.
- (void)openURLInBrowser:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    SFSafariViewController *vc = [[SFSafariViewController alloc] initWithURL:url];
    vc.delegate = self;
    [self presentViewController:vc animated:YES completion:nil];
}

// -[DPSettingsViewController openChangelog]
- (void)openChangelog {
    DPChangelogViewController *cl = [[DPChangelogViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:cl];
    [self.navigationController presentViewController:nav animated:YES completion:nil];
}

// -[DPSettingsViewController resetPreferences]
- (void)resetPreferences {
    [[DPUserPreferences sharedPreferences] resetPreferences];
    [self.tableView reloadData];
}

// Debug rows from original binary (populateDebugData / openDebugDirectory) are DRM-gated
// in the IDA binary (appear only if .dp_response.dat exists under Caches/com.creaturecoding.diskprobe);
// they are not emitted here.

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError *)error {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - SFSafariViewControllerDelegate

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Data sources (ported 1:1 from IDA)

// -[DPSettingsViewController cacheExpirationValues] @ 0x10002f3c4
- (NSArray<NSNumber *> *)cacheExpirationValues {
    return @[@1800, @3600, @7200, @10800, @21600, @43200,
             @57600, @86400, @172800, @259200, @432000, @604800];
}

// -[DPSettingsViewController cacheExpirationTitles] @ 0x10002f658
- (NSArray<NSString *> *)cacheExpirationTitles {
    NSArray *values = [self cacheExpirationValues];
    NSDateComponentsFormatter *f = [NSDateComponentsFormatter new];
    f.allowedUnits = NSCalendarUnitMinute | NSCalendarUnitHour | NSCalendarUnitDay | NSCalendarUnitWeekOfMonth;
    f.unitsStyle = NSDateComponentsFormatterUnitsStyleFull;
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *v in values) {
        NSString *s = [f stringFromTimeInterval:(NSTimeInterval)v.integerValue];
        [out addObject:s ?: @""];
    }
    return [out copy];
}

// -[DPSettingsViewController cacheExpirationShortTitles] @ 0x10002f850
- (NSArray<NSString *> *)cacheExpirationShortTitles {
    NSArray *values = [self cacheExpirationValues];
    NSDateComponentsFormatter *f = [NSDateComponentsFormatter new];
    f.allowedUnits = NSCalendarUnitMinute | NSCalendarUnitHour | NSCalendarUnitDay | NSCalendarUnitWeekOfMonth;
    f.unitsStyle = NSDateComponentsFormatterUnitsStyleShort;
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *v in values) {
        NSString *s = [f stringFromTimeInterval:(NSTimeInterval)v.integerValue];
        [out addObject:s ?: @""];
    }
    return [out copy];
}

// -[DPSettingsViewController contentSizeTitles] @ 0x10002fa48
- (NSArray<NSString *> *)contentSizeTitles {
    return @[NSLocalizedString(@"Extra Small", nil),
             NSLocalizedString(@"Small", nil),
             NSLocalizedString(@"Medium", nil),
             NSLocalizedString(@"Large", nil),
             NSLocalizedString(@"Extra Large", nil),
             NSLocalizedString(@"Extra Extra Large", nil)];
}

// -[DPSettingsViewController contentSizeValues] @ 0x10002faec
// The binary stores a 12-entry UIContentSizeCategory table in
// -[DPUserPreferences contentSize]. The settings UI surfaces the first six
// non-accessibility categories.
- (NSArray<UIContentSizeCategory> *)contentSizeValues {
    return @[UIContentSizeCategoryExtraSmall,
             UIContentSizeCategorySmall,
             UIContentSizeCategoryMedium,
             UIContentSizeCategoryLarge,
             UIContentSizeCategoryExtraLarge,
             UIContentSizeCategoryExtraExtraLarge];
}

// -[DPSettingsViewController interfaceInteractionTypeValues] @ 0x10002fc78
- (NSArray<NSNumber *> *)interfaceInteractionTypeValues {
    return @[@0, @1, @2];
}

// -[DPSettingsViewController interfaceInteractionTypeNames] @ 0x10002fd7c
- (NSArray<NSString *> *)interfaceInteractionTypeNames {
    return @[NSLocalizedString(@"No Interaction", nil),
             NSLocalizedString(@"Peek and Pop", nil),
             NSLocalizedString(@"Context Menus", nil)];
}

@end
