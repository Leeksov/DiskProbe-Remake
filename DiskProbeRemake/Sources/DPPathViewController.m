#import "DPPathViewController.h"
#import "DPPathTableViewCell.h"
#import "DPPathCollectionViewCell.h"
#import "DPAlert.h"
#import "DPCatalog.h"
#import "DPUserPreferences.h"
#import "DPHelper.h"
#import "UIColor+DP.h"
#import "UIImage+DP.h"
#import "DPSettingsViewController.h"
#import "DPFilterAlertViewController.h"
#import "DPContextAction.h"
#import "DPContextActionDataSource.h"
#import "DPPathInfo.h"
#import "UIViewController+DP.h"
#import <QuickLook/QuickLook.h>

// Notification names (matching original binary)
static NSString *const kDPReloadPathData            = @"DPReloadPathData";
static NSString *const kDPSetGraphBarPrompt         = @"DPSetGraphBarPrompt";
static NSString *const kDPNotificationRefreshData   = @"DPNotificationRefreshData";
static NSString *const kDPNotificationSortData      = @"DPNotificationSortData";
static NSString *const kDPNotificationSortDataIfNeeded = @"DPNotificationSortDataIfNeeded";
static NSString *const kDPNotificationSetViewType   = @"DPNotificationSetViewType";

@interface DPPathViewController ()
@property (nonatomic, assign) NSInteger activeViewType;  // 0=table, 1=collection
@property (nonatomic, weak) UISearchController *searchController;
@property (nonatomic, weak) DPNavigationPathView *navigationPathView;
@property (nonatomic, strong) UIDocumentInteractionController *interactionController;
@property (nonatomic, strong) DPInfoHeader *tableHeader;
@property (nonatomic, strong) DPInfoHeader *collectionHeader;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIBarButtonItem *sortButton;
@property (nonatomic, strong) UIBarButtonItem *editButton;
@property (nonatomic, strong) UIBarButtonItem *spaceItem;
@property (nonatomic, strong) UIBarButtonItem *volumeItem;
@property (nonatomic, strong) UIBarButtonItem *countItem;
@property (nonatomic, strong) NSArray *footerItems;
@property (nonatomic, assign) BOOL dataChanged;
@property (nonatomic, copy) NSString *totalSize;

// Preview items
@property (nonatomic, strong) NSArray *previewItems;
@property (nonatomic, strong) QLPreviewController *previewController;
@end

@implementation DPPathViewController {
    BOOL _pendingReload;
    BOOL _swipeActive;
}

+ (instancetype)directoryViewControllerWithDirectory:(NSString *)directory {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    DPPathViewController *vc = [storyboard instantiateViewControllerWithIdentifier:@"DPPathViewController"];
    [vc.dataSource setDirectory:directory];
    return vc;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    _dataSource = [DPDirectoryDataSource dataSourceWithDelegate:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSLog(@"[DPPathVC] viewDidLoad collectionView=%@ frame=%@ layout=%@ tableView=%@ frame=%@",
          _collectionView, NSStringFromCGRect(_collectionView.frame),
          _collectionView.collectionViewLayout,
          _tableView, NSStringFromCGRect(_tableView.frame));

    // Restore saved view type
    _activeViewType = [DPUserPreferences sharedPreferences].pathViewType;

    // Collection view: register header + allow multi-select
    [_collectionView registerClass:[DPInfoHeader class]
        forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
               withReuseIdentifier:@"DPCollectionViewInfoHeader"];
    _collectionView.allowsMultipleSelection = YES;

    // Search controller
    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.searchResultsUpdater = self;
    searchController.hidesNavigationBarDuringPresentation = NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    searchController.dimsBackgroundDuringPresentation = NO;
#pragma clang diagnostic pop
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.searchBar.delegate = self;
    searchController.searchBar.scopeButtonTitles = @[
        NSLocalizedString(@"Exact", nil),
        NSLocalizedString(@"Wildcard", nil),
    ];
    searchController.searchBar.selectedScopeButtonIndex = [DPUserPreferences sharedPreferences].searchMode;
    self.navigationItem.searchController = searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    _searchController = searchController;

    // Custom nav title (DPNavigationPathView)
    DPNavigationPathView *pathView = [[DPNavigationPathView alloc] initWithTitle:self.title
                                                                        delegate:self
                                                               forNavigationItem:self.navigationItem];
    self.navigationItem.titleView = pathView;
    _navigationPathView = (DPNavigationPathView *)self.navigationItem.titleView;

    // Document interaction controller
    self.interactionController = [UIDocumentInteractionController new];

    // Table header (uses view width + dataSource.data)
    CGFloat width = self.view.bounds.size.width;
    _tableHeader = [[DPInfoHeader alloc] initWithWidth:width
                                              delegate:self
                                                  info:self.dataSource.data];

    // Force-touch / peek-and-pop registration (binary calls this here)
    [self forceTouchInitialize];

    // Notification observers (6 total)
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSOperationQueue *mq = [NSOperationQueue mainQueue];
    __weak typeof(self) weakSelf = self;

    [nc addObserverForName:kDPReloadPathData object:nil queue:mq usingBlock:^(NSNotification *note) {
        [weakSelf refreshActiveView];
    }];
    [nc addObserverForName:kDPSetGraphBarPrompt object:nil queue:mq usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) s = weakSelf; if (!s) return;
        [s.tableHeader.graph setPrompt:note.object];
        [s.collectionHeader.graph setPrompt:note.object];
    }];
    [nc addObserverForName:kDPNotificationRefreshData object:nil queue:mq usingBlock:^(NSNotification *note) {
        [weakSelf refreshActiveView];
        [weakSelf _updateFooterLabels];
        [weakSelf _updateHeaderLabels];
    }];
    [nc addObserverForName:kDPNotificationSortData object:nil queue:mq usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) s = weakSelf; if (!s) return;
        [s.dataSource sort];
    }];
    [nc addObserverForName:kDPNotificationSortDataIfNeeded object:nil queue:mq usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) s = weakSelf; if (!s) return;
        [s.dataSource sortIfNeeded];
    }];
    [nc addObserverForName:kDPNotificationSetViewType object:nil queue:mq usingBlock:^(NSNotification *note) {
        // DPFilterAlertViewController posts this with object:nil after updating
        // the pref. Reading note.object here yields 0 and always snaps back to
        // the table. Fall back to the preference when no payload is attached.
        NSInteger viewType = note.object ? [note.object integerValue]
                                         : [DPUserPreferences sharedPreferences].pathViewType;
        [weakSelf setViewActive:viewType];
    }];

    // Table view multi-select
    _tableView.allowsMultipleSelection = YES;
    _tableView.allowsMultipleSelectionDuringEditing = YES;

    // Editing toolbar: [Select All | flexibleSpace | Trash]
    UIBarButtonItem *selectAllItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Select All", nil)
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(handleSelectAll)];
    UIBarButtonItem *editFlex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                              target:nil
                                                                              action:nil];
    UIBarButtonItem *trashItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                               target:self
                                                                               action:@selector(handleDeleteSelectedItems)];
    self.toolbarItems = @[selectAllItem, editFlex, trashItem];

    // Refresh control (shared between table + collection)
    _refreshControl = [[UIRefreshControl alloc] init];
    _tableView.refreshControl = _refreshControl;
    _collectionView.refreshControl = _refreshControl;
    [_refreshControl addTarget:self action:@selector(handleRefreshData) forControlEvents:UIControlEventValueChanged];

    // Footer title text attributes: caption1 font + kern 1.0 (applied for Normal + Highlighted)
    NSDictionary *footerAttribs = @{
        NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1],
        NSKernAttributeName: @1,
    };

    // Flexible space — reused across footer slots (binary uses SAME instance 4x)
    UIBarButtonItem *footerFlex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                target:nil
                                                                                action:nil];

    // Space used label
    _spaceItem = [[UIBarButtonItem alloc] initWithTitle:[[DPCatalog sharedCatalog] usedSpaceStringForVolumeAtPath:self.dataSource.directory]
                                                  style:UIBarButtonItemStylePlain
                                                 target:nil
                                                 action:nil];
    // Volume label
    _volumeItem = [[UIBarButtonItem alloc] initWithTitle:[[DPCatalog sharedCatalog] volumeForPath:self.dataSource.directory]
                                                   style:UIBarButtonItemStylePlain
                                                  target:nil
                                                  action:nil];
    // Item count label
    _countItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"0 items", nil)
                                                  style:UIBarButtonItemStylePlain
                                                 target:nil
                                                 action:nil];

    _footerItems = @[footerFlex, _spaceItem, footerFlex, _volumeItem, footerFlex, _countItem, footerFlex];
    for (UIBarButtonItem *item in _footerItems) {
        [item setTitleTextAttributes:footerAttribs forState:UIControlStateNormal];
        [item setTitleTextAttributes:footerAttribs forState:UIControlStateHighlighted];
    }

    // Tint only the three label items (binary does not tint flexible-spaces)
    UIColor *secondaryColor = [UIColor dp_secondaryLabelColor];
    _countItem.tintColor = secondaryColor;
    _spaceItem.tintColor = secondaryColor;
    _volumeItem.tintColor = secondaryColor;

    // Sort button (SFSymbol)
    _sortButton = [[UIBarButtonItem alloc] initWithImage:[UIImage dp_systemImageNamed:@"line.horizontal.3.decrease.circle"]
                                                   style:UIBarButtonItemStylePlain
                                                  target:self
                                                  action:@selector(handlePresentOptionsAlert:)];
    // Edit button
    _editButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
                                                                target:self
                                                                action:@selector(handleCycleEditingMode)];

    // Footer toolbar — binary constructs with CGRectZero frame
    UIToolbar *footer = [[UIToolbar alloc] initWithFrame:CGRectZero];
    [footer setBackgroundImage:[UIImage new] forToolbarPosition:UIToolbarPositionAny barMetrics:UIBarMetricsDefault];
    footer.backgroundColor = [UIColor clearColor];
    [footer setItems:_footerItems animated:NO];
    footer.barTintColor = [UIColor clearColor];
    _tableView.tableFooterView = footer;

    // Table header
    _tableView.tableHeaderView = _tableHeader;

    // Apply saved view type
    [self setViewActive:[DPUserPreferences sharedPreferences].pathViewType];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (!_dataSource.directory) {
        [self _createNavigationChain];
    }
    if (_dataChanged) {
        [_dataSource refreshData];
        _dataChanged = NO;
    }

    // Save last opened directory
    [[DPUserPreferences sharedPreferences] setLastOpenDirectory:_dataSource.directory];
    [self _updateFooterLabels];
    [_dataSource sortIfNeeded];

    // Toolbar visibility
    [self.navigationController setToolbarHidden:!self.isEditing animated:NO];

    // Nav bar buttons
    self.navigationItem.rightBarButtonItems = @[_editButton, _sortButton];

    // Update title from path info
    self.title = _dataSource.pathInfo.displayName;

    // Force nav bar refresh
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self.navigationController setNavigationBarHidden:NO animated:NO];
}

- (void)setTitle:(NSString *)title {
    [super setTitle:title];
    [(DPNavigationPathView *)self.navigationItem.titleView setTitle:title];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"DPFilterAlert"]) {
        UIViewController *dest = segue.destinationViewController;
        UIPopoverPresentationController *popover = dest.popoverPresentationController;
        if (popover) {
            popover.delegate = self;
            if ([sender isKindOfClass:[UIBarButtonItem class]])
                popover.barButtonItem = sender;
            else if ([sender isKindOfClass:[UIGestureRecognizer class]])
                popover.sourceView = [(UIGestureRecognizer *)sender view];
            else if ([sender isKindOfClass:[UIButton class]] || [sender isKindOfClass:[UIView class]])
                popover.sourceView = sender;
        }
        [dest performSelector:@selector(reloadData) withObject:nil];
    }
}

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller {
    return UIModalPresentationNone;
}

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller
                                                               traitCollection:(UITraitCollection *)traitCollection {
    return UIModalPresentationNone;
}

#pragma mark - View type

- (void)setViewActive:(NSInteger)viewType {
    NSLog(@"[DPPathVC] setViewActive:%ld (cvFrame=%@ tvFrame=%@ dataCount=%lu)",
          (long)viewType,
          NSStringFromCGRect(_collectionView.frame),
          NSStringFromCGRect(_tableView.frame),
          (unsigned long)_dataSource.data.count);
    _activeViewType = viewType;
    _tableView.hidden = (viewType != 0);
    _collectionView.hidden = (viewType != 1);
    if (viewType == 1) {
        _collectionView.dataSource = self;
        _collectionView.delegate = self;
        // Flow layout may have cached a zero-width item size from when the
        // collection view was hidden / never laid out. Invalidate so the
        // sizeForItemAtIndexPath delegate callback recomputes against the
        // current bounds once the view is visible.
        UICollectionViewLayout *layout = _collectionView.collectionViewLayout;
        if ([layout isKindOfClass:[UICollectionViewFlowLayout class]]) {
            UICollectionViewFlowLayout *flow = (UICollectionViewFlowLayout *)layout;
            // Provide a non-zero estimated size so the first pass is never zero.
            CGFloat w = _collectionView.bounds.size.width;
            if (w <= 0) w = self.view.bounds.size.width;
            CGFloat itemW = (w / 3.0) - 8.0;
            if (itemW < 1) itemW = 100;
            flow.estimatedItemSize = CGSizeZero; // opt out of self-sizing
            flow.itemSize = CGSizeMake(itemW, itemW + 40.0);
        }
        [layout invalidateLayout];
        [_collectionView reloadData];
        [_collectionView layoutIfNeeded];
    } else {
        _tableView.dataSource = self;
        _tableView.delegate = self;
        [_tableView reloadData];
    }
}

- (void)refreshActiveView {
    // If the user is editing the table (multi-select) or mid-swipe on a row,
    // reloading the table would cancel their selection / dismiss the swipe.
    // Defer until the gesture ends.
    if (_activeViewType == 0 && (self.isEditing || _swipeActive)) {
        _pendingReload = YES;
        return;
    }
    _pendingReload = NO;
    if (_activeViewType == 0) {
        [_tableView reloadData];
    } else {
        [_collectionView reloadData];
    }
}

- (void)_flushPendingReloadIfNeeded {
    if (_pendingReload && !self.isEditing && !_swipeActive) {
        _pendingReload = NO;
        [self refreshActiveView];
    }
}

#pragma mark - Navigation

- (void)_createNavigationChain {
    // The storyboard's initial VC represents "/". On launch we restore the
    // previously open directory; rather than simply re-pointing this root VC
    // at that deep path (which would leave the nav stack with a single entry
    // and no back button), we keep "/" as the base and push a VC for each
    // ancestor so the user can walk back up.
    NSString *lastDir = [DPUserPreferences sharedPreferences].lastOpenDirectory;
    if (lastDir.length == 0) lastDir = @"/";

    // Root stays pointed at "/"
    [_dataSource setDirectory:@"/"];

    if ([lastDir isEqualToString:@"/"] || lastDir.length == 0) {
        return;
    }

    // Build ancestor paths: e.g. "/private/var/MobileSoftwareUpdate"
    //   -> ["/private", "/private/var", "/private/var/MobileSoftwareUpdate"]
    NSArray<NSString *> *components = [lastDir pathComponents];
    NSMutableArray<UIViewController *> *stack = [NSMutableArray array];
    [stack addObject:self]; // root ("/") controller from storyboard

    NSString *accum = @"";
    for (NSString *comp in components) {
        if ([comp isEqualToString:@"/"]) continue; // skip the leading "/"
        accum = [accum stringByAppendingFormat:@"/%@", comp];
        DPPathViewController *vc =
            [DPPathViewController directoryViewControllerWithDirectory:accum];
        [stack addObject:vc];
    }

    UINavigationController *nav = self.navigationController;
    if (nav && stack.count > 1) {
        // Defer until after the current viewWillAppear finishes so UIKit is
        // in a consistent state before we replace the stack.
        dispatch_async(dispatch_get_main_queue(), ^{
            [nav setViewControllers:stack animated:NO];
        });
    }
}

- (void)goToDirectory:(NSString *)directory animated:(BOOL)animated {
    // Build the full ancestor chain so the nav stack contains every directory
    // from "/" down to `directory`. Preserves the ability to tap "<" back up
    // through each level regardless of how we arrived here (e.g. navigating
    // to a path typed into the path bar, or via -[DPAppDelegate navigateToPath:]).
    if (directory.length == 0) return;

    UINavigationController *nav = self.navigationController;
    if (!nav) return;

    // Find the existing root ("/") controller at the bottom of the stack.
    // If present, reuse it as the base; otherwise treat `self` as the base.
    DPPathViewController *rootVC = nil;
    if (nav.viewControllers.count > 0 &&
        [nav.viewControllers.firstObject isKindOfClass:[DPPathViewController class]]) {
        DPPathViewController *candidate = (DPPathViewController *)nav.viewControllers.firstObject;
        if ([candidate.dataSource.directory isEqualToString:@"/"]) {
            rootVC = candidate;
        }
    }

    NSMutableArray<UIViewController *> *stack = [NSMutableArray array];
    [stack addObject:(rootVC ?: self)];

    if (![directory isEqualToString:@"/"]) {
        NSArray<NSString *> *components = [directory pathComponents];
        NSString *accum = @"";
        for (NSString *comp in components) {
            if ([comp isEqualToString:@"/"]) continue;
            accum = [accum stringByAppendingFormat:@"/%@", comp];
            DPPathViewController *vc =
                [DPPathViewController directoryViewControllerWithDirectory:accum];
            [stack addObject:vc];
        }
    }

    [nav setViewControllers:stack animated:animated];
}

- (void)showControllerForInfo:(DPPathInfo *)info {
    if (info.isDirectory) {
        // For symlinks, navigate to the resolved target. Fall back to the raw
        // path if the symlink didn't resolve (dangling link).
        NSString *dir = (info.isSymbolicLink && info.symbolicPath.path.length)
            ? info.symbolicPath.path
            : info.path.path;
        DPPathViewController *vc = [DPPathViewController directoryViewControllerWithDirectory:dir];
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        // Show Quick Look preview
        [self fetchPreviewItems];
        NSIndexPath *indexPath = [_dataSource indexPathForInfo:info];
        if (indexPath) {
            QLPreviewController *qlvc = [[QLPreviewController alloc] init];
            qlvc.dataSource = self;
            qlvc.delegate = self;
            qlvc.currentPreviewItemIndex = indexPath.row;
            _previewController = qlvc;
            [self.navigationController pushViewController:qlvc animated:YES];
        }
    }
}

#pragma mark - Footer and Header labels

- (void)_updateFooterLabels {
    NSUInteger count = _dataSource.data.count;
    NSNumber *countNumber = [NSNumber numberWithUnsignedInteger:count];
    NSString *localizedCount = [NSNumberFormatter localizedStringFromNumber:countNumber numberStyle:NSNumberFormatterDecimalStyle];
    NSString *plural = (count == 1) ? @"" : @"s";
    _countItem.title = [NSString stringWithFormat:@"%@ item%@", localizedCount, plural];

    NSString *directory = _dataSource.directory;
    _spaceItem.title = [[DPCatalog sharedCatalog] usedSpaceStringForVolumeAtPath:directory];
    _volumeItem.title = [[DPCatalog sharedCatalog] volumeForPath:directory];
}

- (void)_updateHeaderLabels {
    [self _updateHeaderLabelsWithString1:nil string2:nil];
}

- (void)_updateHeaderLabelsWithString1:(NSString *)string1 string2:(NSString *)string2 {
    NSString *leftString = string1;
    NSString *rightString = string2;

    if (!leftString || !rightString) {
        NSString *filter = _dataSource.filter;
        if (filter.length > 0) {
            // Search results: sum bytes of filtered items. Skip symlinks —
            // their bytes live elsewhere (either already counted via the real
            // parent in this listing, or entirely off this mount).
            unsigned long long totalBytes = 0;
            for (DPPathInfo *info in _dataSource.data) {
                if (info.isSymbolicLink) continue;
                totalBytes += info.bytes;
            }
            NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:(long long)totalBytes
                                                               countStyle:NSByteCountFormatterCountStyleFile];
            leftString = [NSString stringWithFormat:
                NSLocalizedString(@"Results Size:\n%@", @""), sizeStr];

            NSNumber *countNumber = [NSNumber numberWithUnsignedInteger:_dataSource.data.count];
            NSString *localizedCount = [NSNumberFormatter localizedStringFromNumber:countNumber
                                                                        numberStyle:NSNumberFormatterDecimalStyle];
            rightString = [NSString stringWithFormat:
                NSLocalizedString(@"Search Results:\n%@", @""), localizedCount];
        } else {
            // Sum direct children: for files use bytes, for directories
            // look up cached size in DPCatalog. Unresolved directories
            // contribute 0 until their async compute finishes, then the
            // catalog's debounced notification reloads us.
            DPCatalog *cat = [DPCatalog sharedCatalog];
            unsigned long long totalBytes = 0;
            for (DPPathInfo *info in _dataSource.data) {
                // Skip symlinks — their target is either already counted by
                // the real parent visible in this listing (e.g. /var -> /private/var
                // at "/", where /private also appears) or lives off this mount.
                // Either way, resolving + summing them would double-count.
                if (info.isSymbolicLink) continue;
                if (info.isDirectory) {
                    totalBytes += [cat sizeForPath:info.path.path];
                } else {
                    totalBytes += info.bytes;
                }
            }
            NSString *sizeStr = totalBytes > 0
                ? [NSByteCountFormatter stringFromByteCount:(long long)totalBytes
                                                 countStyle:NSByteCountFormatterCountStyleFile]
                : @"—";
            leftString = [NSString stringWithFormat:
                NSLocalizedString(@"Directory Size:\n%@", @""), sizeStr];

            NSNumber *countNumber = [NSNumber numberWithUnsignedInteger:_dataSource.data.count];
            NSString *localizedCount = [NSNumberFormatter localizedStringFromNumber:countNumber
                                                                        numberStyle:NSNumberFormatterDecimalStyle];
            rightString = [NSString stringWithFormat:
                NSLocalizedString(@"Items:\n%@", @""), localizedCount];
        }
    }

    [_tableHeader setAttributedText:(NSAttributedString *)leftString label:0];
    [_tableHeader setAttributedText:(NSAttributedString *)rightString label:2];
    if (_collectionHeader) {
        [_collectionHeader setAttributedText:(NSAttributedString *)leftString label:0];
        [_collectionHeader setAttributedText:(NSAttributedString *)rightString label:2];
    }

    // Update bar graph (not in binary's _updateHeaderLabels, but kept from prior behavior).
    // Skip symlinks for the same reason as the Directory Size sum above — their
    // bytes belong to some other tree and would be double-counted alongside
    // the real parent.
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (DPPathInfo *info in _dataSource.data) {
        if (info.isSymbolicLink) continue;
        unsigned long long b = info.bytes;
        if (b > 0 && info.path.path) dict[info.path.path] = @(b);
    }
    [_tableHeader.graph setDataSourceIfChanged:dict];
    [_collectionHeader.graph setDataSourceIfChanged:dict];
}

#pragma mark - Handle actions

- (void)handleShowPathNavigationSearch {
    UINavigationItem *navItem = self.navigationItem;
    DPNavigationPathView *pathView = (DPNavigationPathView *)navItem.titleView;
    [pathView showTextFieldWithString:_dataSource.directory];
}

- (void)handlePresentOptionsAlert:(id)sender {
    [self performSegueWithIdentifier:@"DPFilterAlert" sender:sender];
}

- (void)handleSettingsItemTapped:(id)sender {
    DPSettingsViewController *settings = [DPSettingsViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    [self.navigationController presentViewController:nav animated:YES completion:nil];
}

- (void)handleCycleEditingMode {
    [self setEditing:!self.isEditing animated:YES];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];

    // Propagate to both list and grid views so selection circles appear.
    if ([_tableView isEditing] != editing) {
        [_tableView setEditing:editing animated:animated];
    }
    SEL setEditingSel = @selector(setEditing:animated:);
    if ([_collectionView respondsToSelector:setEditingSel]) {
        NSMethodSignature *sig = [_collectionView methodSignatureForSelector:setEditingSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        inv.target = _collectionView;
        inv.selector = setEditingSel;
        BOOL e = editing, a = animated;
        [inv setArgument:&e atIndex:2];
        [inv setArgument:&a atIndex:3];
        [inv invoke];
    }

    // Show/hide the bottom toolbar: [Select All | space | Trash]
    [self setToolbarItems:[self _editingToolbarItemsSelected:NO] animated:animated];
    [self.navigationController setToolbarHidden:!editing animated:animated];

    // Swap nav bar button between Edit and Done.
    UIBarButtonSystemItem sysItem = editing ? UIBarButtonSystemItemDone : UIBarButtonSystemItemEdit;
    _editButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:sysItem
                                                                target:self
                                                                action:@selector(handleCycleEditingMode)];
    self.navigationItem.rightBarButtonItems = @[_editButton, _sortButton];

    // When exiting, clear any lingering selection.
    if (!editing) {
        for (NSIndexPath *ip in [_tableView.indexPathsForSelectedRows copy]) {
            [_tableView deselectRowAtIndexPath:ip animated:NO];
        }
        for (NSIndexPath *ip in [_collectionView.indexPathsForSelectedItems copy]) {
            [_collectionView deselectItemAtIndexPath:ip animated:NO];
        }
        // Catch up on any reload that was deferred while editing.
        [self _flushPendingReloadIfNeeded];
    }
}

- (void)tableView:(UITableView *)tableView willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    _swipeActive = YES;
}

- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    _swipeActive = NO;
    [self _flushPendingReloadIfNeeded];
}

// Paths whose deletion is very likely to bootloop the device. A direct
// match or any sub-path of these triggers an extra confirmation dialog.
static NSArray<NSString *> *DPDangerousPaths(void) {
    static NSArray<NSString *> *paths;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        paths = @[
            @"/", @"/System", @"/System/Library",
            @"/private", @"/private/var", @"/private/var/mobile", @"/private/var/root",
            @"/var", @"/var/mobile", @"/var/root",
            @"/var/jb", @"/var/jb/Applications", @"/var/jb/usr", @"/var/jb/Library",
            @"/usr", @"/usr/lib", @"/usr/libexec", @"/usr/bin", @"/usr/sbin",
            @"/bin", @"/sbin", @"/etc", @"/dev",
            @"/Applications", @"/Library",
        ];
    });
    return paths;
}

// Returns a non-nil warning string when the given path is a system-critical
// directory whose deletion is likely to bootloop the device.
static NSString *DPBootloopWarningForPath(NSString *path) {
    for (NSString *p in DPDangerousPaths()) {
        if ([path isEqualToString:p]) {
            return [NSString stringWithFormat:NSLocalizedString(@"\"%@\" is a critical system directory. Deleting it will very likely bootloop the device and force a full restore.", nil), path];
        }
    }
    return nil;
}

- (NSArray<DPPathInfo *> *)_currentSelectedInfos {
    NSMutableArray<DPPathInfo *> *out = [NSMutableArray array];
    NSArray *selected = _activeViewType == 0
        ? _tableView.indexPathsForSelectedRows
        : _collectionView.indexPathsForSelectedItems;
    for (NSIndexPath *ip in selected) {
        DPPathInfo *info = [_dataSource infoAtIndexPath:ip];
        if (info) [out addObject:info];
    }
    return out;
}

- (void)handleDeleteSelectedItems {
    __weak typeof(self) weakSelf = self;
    NSArray<DPPathInfo *> *infos = [self _currentSelectedInfos];
    // Collect any dangerous paths in the selection.
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];
    for (DPPathInfo *info in infos) {
        NSString *w = DPBootloopWarningForPath(info.path.path);
        if (w) [warnings addObject:w];
    }
    void (^proceed)(void) = ^{
        [weakSelf _deleteSelectedItems];
    };
    if (warnings.count > 0) {
        NSString *joined = [warnings componentsJoinedByString:@"\n\n"];
        [DPAlert makeAlert:^(DPAlert *alert) {
            [alert title:^{ return NSLocalizedString(@"⚠️ Bootloop Risk", nil); }];
            [alert message:^{ return [joined stringByAppendingString:@"\n\nAre you absolutely sure?"]; }];
            [alert destructiveButton:NSLocalizedString(@"I understand, delete", nil) handler:proceed];
            [alert cancelButton];
        } showFrom:self.navigationController];
        return;
    }
    [DPAlert makeAlert:^(DPAlert *alert) {
        [alert title:^{ return NSLocalizedString(@"Delete Selected", nil); }];
        [alert message:^{ return NSLocalizedString(@"Delete all selected items?", nil); }];
        [alert destructiveButton:NSLocalizedString(@"Delete", nil) handler:proceed];
        [alert cancelButton];
    } showFrom:self.navigationController];
}

- (void)_deleteSelectedItems {
    NSArray *selectedPaths = _activeViewType == 0 ?
        _tableView.indexPathsForSelectedRows :
        _collectionView.indexPathsForSelectedItems;
    for (NSIndexPath *indexPath in selectedPaths) {
        DPPathInfo *info = [_dataSource infoAtIndexPath:indexPath];
        if (!info) continue;
        [[DPCatalog sharedCatalog] removeItemAtURL:info.path itemSize:info.bytes updatingCatalog:YES];
    }
    [_dataSource refreshData];
    [self setEditing:NO animated:YES];
}

- (void)handleDeleteItemAtIndex:(NSIndexPath *)indexPath {
    DPPathInfo *info = [_dataSource infoAtIndexPath:indexPath];
    __weak typeof(self) weakSelf = self;
    NSString *warning = DPBootloopWarningForPath(info.path.path);
    void (^del)(void) = ^{
        [[DPCatalog sharedCatalog] removeItemAtURL:info.path itemSize:info.bytes updatingCatalog:YES];
        __strong typeof(weakSelf) s = weakSelf; if (!s) return; [s.dataSource refreshData];
    };
    if (warning) {
        [DPAlert makeAlert:^(DPAlert *alert) {
            [alert title:^{ return NSLocalizedString(@"⚠️ Bootloop Risk", nil); }];
            [alert message:^{ return [warning stringByAppendingString:@"\n\nAre you absolutely sure?"]; }];
            [alert destructiveButton:NSLocalizedString(@"I understand, delete", nil) handler:del];
            [alert cancelButton];
        } showFrom:self.navigationController];
        return;
    }
    [DPAlert makeAlert:^(DPAlert *alert) {
        [alert title:^{ return [NSString stringWithFormat:NSLocalizedString(@"Delete \"%@\"?", nil), info.displayName]; }];
        [alert destructiveButton:NSLocalizedString(@"Delete", nil) handler:del];
        [alert cancelButton];
    } showFrom:self.navigationController];
}

- (void)handleUninstallItemAtIndex:(NSIndexPath *)indexPath {
    DPPathInfo *info = [_dataSource infoAtIndexPath:indexPath];
    __weak typeof(self) weakSelf = self;
    [DPAlert makeAlert:^(DPAlert *alert) {
        [alert title:^{ return [NSString stringWithFormat:NSLocalizedString(@"Uninstall \"%@\"?", nil), info.displayName]; }];
        [alert destructiveButton:NSLocalizedString(@"Uninstall", nil) handler:^{
            [info uninstallItem];
            __strong typeof(weakSelf) s = weakSelf; if (!s) return; [s.dataSource refreshData];
        }];
        [alert cancelButton];
    } showFrom:self.navigationController];
}

- (void)handleSelectAll {
    NSInteger colSections = [_collectionView numberOfSections];
    for (NSInteger s = 0; s < colSections; s++) {
        NSInteger items = [_collectionView numberOfItemsInSection:s];
        for (NSInteger i = 0; i < items; i++) {
            NSIndexPath *ip = [NSIndexPath indexPathForItem:i inSection:s];
            [_collectionView selectItemAtIndexPath:ip animated:NO scrollPosition:UICollectionViewScrollPositionNone];
        }
    }
    NSInteger tblSections = [_tableView numberOfSections];
    for (NSInteger s = 0; s < tblSections; s++) {
        NSInteger rows = [_tableView numberOfRowsInSection:s];
        for (NSInteger r = 0; r < rows; r++) {
            NSIndexPath *ip = [NSIndexPath indexPathForRow:r inSection:s];
            [_tableView selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
        }
    }
    [self setToolbarItems:[self _editingToolbarItemsSelected:YES]];
}

- (void)handleDeselectAll {
    for (NSIndexPath *ip in [_tableView.indexPathsForSelectedRows copy]) {
        [_tableView deselectRowAtIndexPath:ip animated:NO];
    }
    for (NSIndexPath *ip in [_collectionView.indexPathsForSelectedItems copy]) {
        [_collectionView deselectItemAtIndexPath:ip animated:NO];
    }
    [self setToolbarItems:[self _editingToolbarItemsSelected:NO]];
}

- (NSArray<UIBarButtonItem *> *)_editingToolbarItemsSelected:(BOOL)allSelected {
    NSString *title = allSelected ? NSLocalizedString(@"Deselect All", nil) : NSLocalizedString(@"Select All", nil);
    SEL action = allSelected ? @selector(handleDeselectAll) : @selector(handleSelectAll);
    UIBarButtonItem *toggle = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStylePlain target:self action:action];
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *trash = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(handleDeleteSelectedItems)];
    return @[toggle, space, trash];
}

- (void)setSelectedIndexPaths:(NSArray<NSIndexPath *> *)paths forViewType:(NSInteger)viewType {
    // Sync selection when switching between list/grid. viewType bitmask: 1=collection, 2=table, 0=table-only.
    if (viewType == 0 || viewType == 2) {
        for (NSIndexPath *ip in [_tableView.indexPathsForSelectedRows copy]) {
            [_tableView deselectRowAtIndexPath:ip animated:NO];
        }
    }
    if (viewType == 1 || viewType == 2) {
        for (NSIndexPath *ip in [_collectionView.indexPathsForSelectedItems copy]) {
            [_collectionView deselectItemAtIndexPath:ip animated:NO];
        }
    }
    if (!paths.count) return;
    if (viewType == 0 || viewType == 2) {
        for (NSIndexPath *ip in paths) {
            [_tableView selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
        }
    }
    if (viewType == 1 || viewType == 2) {
        for (NSIndexPath *ip in paths) {
            [_collectionView selectItemAtIndexPath:ip animated:NO scrollPosition:UICollectionViewScrollPositionNone];
        }
    }
}

- (void)handleRefreshData {
    [_dataSource refreshData];
}

#pragma mark - DPDirectoryDataSourceDelegate

- (void)didChangeDirectory:(NSString *)directory {
    // Refresh navigation title
    [self refreshActiveView];
    [self setTitle:_dataSource.pathInfo.displayName];
    self.totalSize = _dataSource.pathInfo.sizeLabel;
    _interactionController.URL = _dataSource.pathInfo.path;
    [self _updateFooterLabels];
    [self _updateHeaderLabels];
    [self refreshActiveView];

    BOOL loading = ![DPCatalog cacheIsLoaded];
    [_tableHeader setAnimating:loading];
    [_collectionHeader setAnimating:loading];
    [_refreshControl endRefreshing];

    if (!self.view.window) _dataChanged = YES;
}

- (void)didChangeSortingMode:(NSInteger)mode {
    [self refreshActiveView];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _dataSource.data.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DPPathTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DPPathTableViewCell" forIndexPath:indexPath];
    DPPathInfo *info = [_dataSource infoAtIndexPath:indexPath];
    [cell refreshWithInfo:info interactionController:_interactionController];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.isEditing) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        DPPathInfo *info = [_dataSource infoAtIndexPath:indexPath];
        [self showControllerForInfo:info];
    }
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldBeginMultipleSelectionInteractionAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView didBeginMultipleSelectionInteractionAtIndexPath:(NSIndexPath *)indexPath {
    [self setEditing:YES animated:YES];
}

- (void)tableViewDidEndMultipleSelectionInteraction:(UITableView *)tableView {}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    DPPathInfo *info = [_dataSource infoAtIndexPath:indexPath];
    BOOL canUninstall = NO;
    if ([info isApplication]) {
        canUninstall = ([info applicationBundle] != nil) && [info isApplicationInstalled];
    }

    // Delete / Uninstall action (red, destructive)
    NSString *deleteTitle = canUninstall ? NSLocalizedString(@"Uninstall", nil) : NSLocalizedString(@"Delete", nil);
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:deleteTitle
                                                                             handler:^(UIContextualAction *action, UIView *view, void (^complete)(BOOL)) {
        if (canUninstall) {
            [self handleUninstallItemAtIndex:indexPath];
        } else {
            [self handleDeleteItemAtIndex:indexPath];
        }
        complete(YES);
    }];

    // Info action (blue) — presents embedded info view controller modally
    UIContextualAction *infoAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                             title:NSLocalizedString(@"Info", nil)
                                                                           handler:^(UIContextualAction *action, UIView *view, void (^complete)(BOOL)) {
        UIViewController *infoVC = [info embeddedInfoViewController];
        [self.navigationController presentViewController:infoVC animated:YES completion:nil];
        complete(YES);
    }];

    // Preview action (purple) — QuickLook, files only. Title is "Info" in the binary.
    UIContextualAction *previewAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                title:NSLocalizedString(@"Info", nil)
                                                                              handler:^(UIContextualAction *action, UIView *view, void (^complete)(BOOL)) {
        QLPreviewController *qlvc = [self quickLookPreviewControllerForInfo:info];
        [self.navigationController presentViewController:qlvc animated:YES completion:nil];
        complete(YES);
    }];

    // Background colors (assignment order in binary: purple, blue, red)
    previewAction.backgroundColor = [UIColor systemPurpleColor];
    infoAction.backgroundColor = [UIColor systemBlueColor];
    deleteAction.backgroundColor = [UIColor systemRedColor];

    // Images (assignment order in binary: trash.fill, info.circle, eye)
    deleteAction.image = [UIImage dp_systemImageNamed:@"trash.fill"];
    infoAction.image = [UIImage dp_systemImageNamed:@"info.circle"];
    previewAction.image = [UIImage dp_systemImageNamed:@"eye"];

    NSArray *actions;
    if ([info isDirectory]) {
        actions = @[deleteAction, infoAction];
    } else {
        actions = @[deleteAction, infoAction, previewAction];
    }

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:actions];
    [config setPerformsFirstActionWithFullSwipe:YES];
    return config;
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _dataSource.data.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    DPPathCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"DPPathCollectionViewCell"
                                                                               forIndexPath:indexPath];
    DPPathInfo *info = [_dataSource infoAtIndexPath:indexPath];
    [cell refreshWithInfo:info interactionController:_interactionController];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.isEditing) {
        DPPathInfo *info = [_dataSource infoAtIndexPath:indexPath];
        [self showControllerForInfo:info];
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView canEditItemAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        DPInfoHeader *header = (DPInfoHeader *)[collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                                  withReuseIdentifier:@"DPCollectionViewInfoHeader"
                                                                                         forIndexPath:indexPath];
        if (!_collectionHeader) {
            _collectionHeader = header;
            _collectionHeader.delegate = self;
        }
        return header;
    }
    return [[UICollectionReusableView alloc] initWithFrame:CGRectZero];
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView
                        layout:(UICollectionViewLayout *)layout
        insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsZero;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)layout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = collectionView.bounds.size.width / 3.0 - 8.0;
    return CGSizeMake(width, width + 40.0);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return 0;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return 0;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self refreshActiveView];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = searchController.searchBar.text;
    _dataSource.filter = text;
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    [[DPUserPreferences sharedPreferences] setSearchMode:selectedScope];
    [self updateSearchResultsForSearchController:_searchController];
}

#pragma mark - DPNavigationPathViewDelegate

- (void)navigationViewWasTapped:(DPNavigationPathView *)view {
    [self handleShowPathNavigationSearch];
}

- (void)navigationViewDidChangePath:(NSString *)path {
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir) {
        [_dataSource setDirectory:path];
    }
}

#pragma mark - QLPreviewControllerDataSource / Delegate

- (void)fetchPreviewItems {
    NSMutableArray *items = [NSMutableArray array];
    for (DPPathInfo *info in _dataSource.data) {
        if (info.isDirectory) continue;
        // For symlinks to files, preview the resolved target.
        NSURL *url = (info.isSymbolicLink && info.symbolicPath) ? info.symbolicPath : info.path;
        if (url) [items addObject:url];
    }
    _previewItems = [items copy];
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return _previewItems.count;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return _previewItems[index];
}

- (BOOL)previewController:(QLPreviewController *)controller shouldOpenURL:(NSURL *)url forPreviewItem:(id<QLPreviewItem>)item {
    return YES;
}

- (QLPreviewController *)quickLookPreviewControllerForInfo:(DPPathInfo *)info {
    [self fetchPreviewItems];
    NSIndexPath *indexPath = [_dataSource indexPathForInfo:info];
    QLPreviewController *vc = [[QLPreviewController alloc] init];
    vc.dataSource = self;
    vc.delegate = self;
    vc.currentPreviewItemIndex = indexPath ? indexPath.row : 0;
    return vc;
}

#pragma mark - Force touch / Peek and Pop

- (BOOL)isForceTouchAvailable {
    UITraitCollection *trait = self.traitCollection;
    if (![trait respondsToSelector:@selector(forceTouchCapability)]) return NO;
    return self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable;
}

- (void)forceTouchInitialize {
    if ([self isForceTouchAvailable]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        id<UIViewControllerPreviewing> ctx = [self registerForPreviewingWithDelegate:(id)self
                                                                           sourceView:self.view];
#pragma clang diagnostic pop
        [self setPreviewingContext:ctx];
    }
}

#pragma mark - Preview controller helpers

- (UIViewController *)previewControllerForInfo:(DPPathInfo *)info {
    return [info embeddedPreviewController];
}

- (UIViewController *)previewControllerForInfoOrNil:(DPPathInfo *)info {
    if (info.isDirectory) return nil;
    return [self previewControllerForInfo:info];
}

#pragma mark - Context action data source

- (DPContextActionDataSource *)contextActionDataSourceForInfo:(DPPathInfo *)info {
    BOOL canUninstall = NO;
    if ([info isApplication]) {
        canUninstall = ([info applicationBundle] != nil) && [info isApplicationInstalled];
    }
    __weak typeof(self) weakSelf = self;
    DPPathInfo *target = info;
    return [DPContextActionDataSource dataSourceWithBuilder:^(DPContextActionDataSource *ds) {
        // Open in Filza (group 1)
        ds.action.title(NSLocalizedString(@"Open in Filza", @""))
                 .image([UIImage dp_systemImageNamed:@"folder"])
                 .handler(^{ [target openInFilza]; })
                 .groupIdentifier(@"1");

        // Open Directory / Open Preview (group 1)
        NSString *openTitle = target.isDirectory
            ? NSLocalizedString(@"Open Directory", @"")
            : NSLocalizedString(@"Open Preview", @"");
        NSString *openImage = target.isDirectory ? @"folder" : @"eye";
        ds.action.title(openTitle)
                 .image([UIImage dp_systemImageNamed:openImage])
                 .handler(^{
                     __strong typeof(weakSelf) s = weakSelf; if (!s) return;
                     [s showControllerForInfo:target];
                 })
                 .groupIdentifier(@"1");

        // Open Info (group 1)
        ds.action.title(NSLocalizedString(@"Open Info", @""))
                 .image([UIImage dp_systemImageNamed:@"info.circle"])
                 .handler(^{
                     __strong typeof(weakSelf) s = weakSelf; if (!s) return;
                     UIViewController *infoVC = [target embeddedInfoViewController];
                     [s.navigationController presentViewController:infoVC animated:YES completion:nil];
                 })
                 .groupIdentifier(@"1");

        // Copy Path (group 2)
        ds.action.title(NSLocalizedString(@"Copy Path", @""))
                 .image([UIImage dp_systemImageNamed:@"doc.on.doc.fill"])
                 .handler(^{ [UIPasteboard generalPasteboard].URL = target.path; })
                 .groupIdentifier(@"2");

        // Copy Name (group 2)
        ds.action.title(NSLocalizedString(@"Copy Name", @""))
                 .image([UIImage dp_systemImageNamed:@"doc.on.doc.fill"])
                 .handler(^{ [UIPasteboard generalPasteboard].string = target.name; })
                 .groupIdentifier(@"2");

        // Delete Item / Uninstall Application (destructive, group 3)
        NSString *delTitle = canUninstall
            ? NSLocalizedString(@"Uninstall Application", @"")
            : NSLocalizedString(@"Delete Item", @"");
        ds.action.title(delTitle)
                 .image([UIImage dp_systemImageNamed:@"trash.fill"])
                 .handler(^{ [target removeOrUninstallItem]; })
                 .destructive(YES)
                 .groupIdentifier(@"3");
    }];
}

#pragma mark - UIContextMenuInteraction (table + collection)

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
                                        point:(CGPoint)point {
    if ([DPUserPreferences sharedPreferences].interfaceInteractionType != 2) return nil;
    if (self.isEditing) return nil;
    DPPathInfo *info = [_dataSource infoAtIndexPath:indexPath];
    if (!info) return nil;

    __weak typeof(self) weakSelf = self;
    UIContextMenuContentPreviewProvider previewProvider = ^UIViewController *(void) {
        UIViewController *preview = [weakSelf previewControllerForInfoOrNil:info];
        if (preview) {
            [preview setPreviewingContextParentController:weakSelf];
        }
        return preview;
    };

    DPContextActionDataSource *ds = [self contextActionDataSourceForInfo:info];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:previewProvider
                                                    actionProvider:ds.actionProvider];
}

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)collectionView
    contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath
                                         point:(CGPoint)point {
    if ([DPUserPreferences sharedPreferences].interfaceInteractionType != 2) return nil;
    if (self.isEditing) return nil;
    DPPathInfo *info = [_dataSource infoAtIndexPath:indexPath];
    if (!info) return nil;

    __weak typeof(self) weakSelf = self;
    UIContextMenuContentPreviewProvider previewProvider = ^UIViewController *(void) {
        UIViewController *preview = [weakSelf previewControllerForInfoOrNil:info];
        if (preview) {
            [preview setPreviewingContextParentController:weakSelf];
        }
        return preview;
    };

    DPContextActionDataSource *ds = [self contextActionDataSourceForInfo:info];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:previewProvider
                                                    actionProvider:ds.actionProvider];
}

@end
