#import "DPTableViewController.h"
#import "DPUserPreferences.h"
#import "UIColor+DP.h"
#import <objc/message.h>

@implementation DPTableViewController

+ (instancetype)tableViewControllerWithPlist:(NSString *)plistName {
    NSString *path = [[NSBundle mainBundle] pathForResource:plistName ofType:@"plist"];
    NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:path];
    DPTableViewController *vc = [[self alloc] initWithData:data];
    return vc;
}

+ (instancetype)tableViewControllerWithDataSource:(NSDictionary *)dataSource {
    return [[self alloc] initWithData:dataSource];
}

+ (instancetype)tableViewControllerWithDataSource:(NSDictionary *)dataSource cellStyle:(UITableViewCellStyle)cellStyle {
    DPTableViewController *vc = [[self alloc] initWithData:dataSource];
    vc.cellStyle = cellStyle;
    return vc;
}

- (instancetype)initWithData:(NSDictionary *)data {
    self = [super init];
    if (self) {
        _data = data;
        _disabledIndexPaths = [NSMutableArray new];
    }
    return self;
}

- (void)loadView {
    [super loadView];
    // If a nib (e.g. via storyboard) already supplied a view and tableView, keep them.
    // Otherwise, build a table view from scratch and use it as the root view.
    if (self.tableView == nil) {
        CGRect frame = self.view ? self.view.bounds : [UIScreen mainScreen].bounds;
        UITableView *tv = [[UITableView alloc] initWithFrame:frame style:UITableViewStyleGrouped];
        self.tableView = tv;
        self.view = self.tableView;
    }
    [self.tableView setDataSource:self];
    [self.tableView setDelegate:self];
    UIColor *bg = [UIColor dp_tableViewGroupedBackgroundColor];
    [self.tableView setBackgroundColor:bg];
    self.disabledIndexPaths = [NSMutableArray new];
}

- (void)setData:(NSDictionary *)data {
    _data = data;
    [self.tableView reloadData];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self.tableView reloadData];
}

#pragma mark - Data helpers

- (NSArray *)_sections {
    return _data[@"sections"];
}

- (NSDictionary *)dataSource {
    return _data;
}

- (NSDictionary *)dataForIndexPath:(NSIndexPath *)indexPath {
    NSArray *sections = [self _sections];
    if (!sections || indexPath.section >= (NSInteger)sections.count) return nil;
    NSDictionary *section = sections[indexPath.section];
    NSArray *rows = section[@"rows"];
    if (!rows || indexPath.row >= (NSInteger)rows.count) return nil;
    return rows[indexPath.row];
}

- (NSIndexPath *)indexPathForPrefsKey:(NSString *)prefsKey {
    NSArray *sections = [self _sections];
    for (NSUInteger s = 0; s < sections.count; s++) {
        NSDictionary *section = sections[s];
        NSArray *rows = section[@"rows"];
        for (NSUInteger r = 0; r < rows.count; r++) {
            NSDictionary *row = rows[r];
            NSString *key = row[@"prefsKey"];
            if ([key isEqualToString:prefsKey]) {
                return [NSIndexPath indexPathForRow:(NSInteger)r inSection:(NSInteger)s];
            }
        }
    }
    return nil;
}

- (UITableViewCellStyle)cellStyleForString:(NSString *)string {
    if ([string isEqualToString:@"subtitle"]) return UITableViewCellStyleSubtitle;
    if ([string isEqualToString:@"value1"]) return UITableViewCellStyleValue1;
    if ([string isEqualToString:@"value2"]) return UITableViewCellStyleValue2;
    return UITableViewCellStyleDefault;
}

- (UITableViewCellAccessoryType)accessoryTypeForString:(NSString *)string {
    if (!string || string.length == 0) return UITableViewCellAccessoryNone;
    if ([string isEqualToString:@"none"]) return UITableViewCellAccessoryNone;
    if ([string isEqualToString:@"checkmark"]) return UITableViewCellAccessoryCheckmark;
    if ([string isEqualToString:@"disclosureIndicator"]) return UITableViewCellAccessoryDisclosureIndicator;
    if ([string isEqualToString:@"detailButton"]) return UITableViewCellAccessoryDetailButton;
    if ([string isEqualToString:@"detailDisclosureButton"]) return UITableViewCellAccessoryDetailDisclosureButton;
    return UITableViewCellAccessoryNone;
}

- (NSString *)stringForDataValue:(id)value {
    if (!value) return nil;
    if ([value isKindOfClass:[NSString class]]) return value;
    return [value description];
}

- (void)setCellForRowAtIndexPath:(NSIndexPath *)indexPath enabled:(BOOL)enabled animated:(BOOL)animated {
    if (enabled) {
        [self.disabledIndexPaths removeObject:indexPath];
    } else {
        if (![self.disabledIndexPaths containsObject:indexPath]) {
            [self.disabledIndexPaths addObject:indexPath];
        }
    }
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (cell) {
        if (animated) {
            [UIView animateWithDuration:0.2 animations:^{
                cell.textLabel.enabled = enabled;
                cell.detailTextLabel.enabled = enabled;
                cell.userInteractionEnabled = enabled;
            }];
        } else {
            cell.textLabel.enabled = enabled;
            cell.detailTextLabel.enabled = enabled;
            cell.userInteractionEnabled = enabled;
        }
    }
}

- (void)dismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)[[self _sections] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray *sections = [self _sections];
    if (section >= (NSInteger)sections.count) return 0;
    NSDictionary *sectionData = sections[section];
    NSArray *rows = sectionData[@"rows"];
    return (NSInteger)rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *rowData = [self dataForIndexPath:indexPath];
    if (!rowData) return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];

    id headerVal = rowData[@"header"];
    id footerVal = rowData[@"footer"];

    NSString *cellType = rowData[@"cellType"];
    NSString *baseType = @"cell";
    if (footerVal) baseType = @"footer";
    if (headerVal) baseType = @"header";
    if (!cellType) cellType = baseType;

    NSString *cellStyleStr = rowData[@"cellStyle"];
    NSString *reuseId = cellStyleStr ? [cellType stringByAppendingString:cellStyleStr] : cellType;

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
    if (!cell) {
        UITableViewCellStyle style = [self cellStyleForString:cellStyleStr];
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:reuseId];
    }

    BOOL enabled = ![self.disabledIndexPaths containsObject:indexPath];
    cell.textLabel.enabled = enabled;
    cell.detailTextLabel.enabled = enabled;
    cell.userInteractionEnabled = enabled;

    cell.detailTextLabel.textColor = [UIColor dp_secondaryLabelColor];
    cell.textLabel.textColor = [UIColor dp_labelColor];

    UIColor *bgColor = (headerVal || footerVal) ? [UIColor clearColor] : [UIColor dp_tableCellBackgroundColor];
    cell.backgroundColor = bgColor;

    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.accessoryView = nil;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;

    if (headerVal || footerVal) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (headerVal) {
            NSString *headerStr = [self stringForDataValue:headerVal];
            cell.detailTextLabel.text = [headerStr uppercaseString];
            cell.detailTextLabel.numberOfLines = 1;
            cell.separatorInset = UIEdgeInsetsMake(0, 10000, 0, 0);
            cell.indentationWidth = -10000;
            cell.indentationLevel = 1;
        } else {
            NSString *footerStr = [self stringForDataValue:footerVal];
            cell.detailTextLabel.text = footerStr;
            cell.detailTextLabel.numberOfLines = 0;
            cell.separatorInset = UIEdgeInsetsMake(0, 10000, 0, 0);
            cell.indentationWidth = -10000;
            cell.indentationLevel = 1;
        }
        return cell;
    }

    NSString *control = rowData[@"control"];
    if (control) {
        if ([control isEqualToString:@"button"]) {
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.textLabel.textColor = self.view.tintColor;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else if ([control isEqualToString:@"switch"]) {
            UISwitch *sw = [UISwitch new];
            NSString *prefsKey = rowData[@"prefsKey"];
            if (prefsKey) {
                [sw addTarget:self action:@selector(controlDidChangeValue:) forControlEvents:UIControlEventValueChanged];
                NSUserDefaults *ud = [[DPUserPreferences sharedPreferences] userDefaults];
                [sw setOn:[ud boolForKey:prefsKey]];
            } else {
                NSString *action = rowData[@"action"];
                if (action) {
                    [self _addAction:NSSelectorFromString(action) forControlEvent:UIControlEventValueChanged inControl:sw];
                }
            }
            sw.onTintColor = self.view.tintColor;
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else {
        NSString *detail = rowData[@"detail"];
        if (detail) {
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            NSString *accStr = rowData[@"accessory"];
            cell.selectionStyle = accStr ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
        }
    }

    NSString *accStr = rowData[@"accessory"];
    cell.accessoryType = [self accessoryTypeForString:accStr];

    NSString *title = [self stringForDataValue:rowData[@"title"]];
    cell.textLabel.text = title;

    NSNumber *titleLinesNum = rowData[@"titleLines"];
    cell.textLabel.numberOfLines = titleLinesNum ? titleLinesNum.integerValue : 1;

    NSString *subtitle = [self stringForDataValue:rowData[@"subtitle"]];
    cell.detailTextLabel.text = subtitle;
    cell.detailTextLabel.numberOfLines = 0;

    UIImage *iconImage = rowData[@"iconImage"];
    if (iconImage) {
        cell.imageView.image = iconImage;
    } else {
        NSString *iconName = rowData[@"icon"];
        if (iconName) {
            cell.imageView.image = [UIImage imageNamed:iconName];
        } else {
            cell.imageView.image = nil;
        }
    }

    NSString *titleColor = rowData[@"titleColor"];
    if (titleColor) {
        cell.textLabel.textColor = [UIColor dp_colorByEvaluatingHexString:titleColor];
    }
    NSString *subtitleColor = rowData[@"subtitleColor"];
    if (subtitleColor) {
        cell.detailTextLabel.textColor = [UIColor dp_colorByEvaluatingHexString:subtitleColor];
    }

    NSNumber *iconUsesLabelColor = rowData[@"iconUsesLabelColor"];
    if (iconUsesLabelColor.boolValue) {
        cell.imageView.tintColor = cell.textLabel.textColor;
    }

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *rowData = [self dataForIndexPath:indexPath];
    id headerVal = rowData[@"header"];
    id footerVal = rowData[@"footer"];
    if (headerVal) {
        NSString *s = [self stringForDataValue:headerVal];
        return (s && s.length > 0) ? 30.0 : 8.0;
    }
    if (footerVal) {
        return 8.0;
    }
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return nil;
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self.disabledIndexPaths containsObject:indexPath]) return nil;
    return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    self.lastSelectedIndexPath = indexPath;

    NSDictionary *rowData = [self dataForIndexPath:indexPath];
    if (!rowData) return;

    __weak DPTableViewController *weakSelf = self;

    void (^actionBlock)(void) = ^{
        void (^block)(void) = rowData[@"block"];
        if (block) {
            block();
            return;
        }
        id action = rowData[@"action"];
        id detail = rowData[@"detail"];
        if (action || detail) {
            id target = rowData[@"target"] ?: weakSelf;
            SEL sel = detail ? NSSelectorFromString(detail) : NSSelectorFromString(action);
            if (target && sel && [target respondsToSelector:sel]) {
                ((void(*)(id, SEL))objc_msgSend)(target, sel);
            }
        }
    };

    NSNumber *dismissBefore = rowData[@"dismissBefore"];
    if (dismissBefore.boolValue) {
        [self dismissViewControllerAnimated:YES completion:actionBlock];
    } else {
        actionBlock();
    }

    NSNumber *dismissAfter = rowData[@"dismissAfter"];
    if (dismissAfter.boolValue) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }

    NSNumber *requiresReload = rowData[@"requiresReloadSection"];
    if (requiresReload.boolValue) {
        NSArray *visible = [tableView indexPathsForVisibleRows];
        [tableView reloadRowsAtIndexPaths:visible withRowAnimation:UITableViewRowAnimationFade];
    }
}

#pragma mark - Control change

- (void)_addAction:(SEL)action forControlEvent:(UIControlEvents)event inControl:(UIControl *)control {
    [control addTarget:self action:action forControlEvents:event];
}

- (void)controlDidChangeValue:(id)sender {
    [self controlDidChangeValue:sender authentication:0];
}

- (void)controlDidChangeValue:(id)sender authentication:(NSUInteger)auth {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *indexPath = [self indexPathForControl:sender];
        if (!indexPath) return;
        NSDictionary *rowData = [self dataForIndexPath:indexPath];
        NSString *prefsKey = rowData[@"prefsKey"];
        if (prefsKey) {
            id ud = [[DPUserPreferences sharedPreferences] userDefaults];
            if ([sender isKindOfClass:[UISwitch class]]) {
                [ud setBool:((UISwitch *)sender).isOn forKey:prefsKey];
            }
            [[DPUserPreferences sharedPreferences] synchronize];
        }
        void (^block)(void) = rowData[@"block"];
        if (block) block();
    });
}

- (NSIndexPath *)indexPathForControl:(UIControl *)control {
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        if (cell.accessoryView == control) {
            return [self.tableView indexPathForCell:cell];
        }
    }
    return nil;
}

@end
