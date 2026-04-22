#import "DPPopoverAlertViewController.h"
#import "UIColor+DP.h"

@implementation DPPopoverAlertViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.backgroundColor = [UIColor clearColor];
    self.view.backgroundColor = [UIColor clearColor];

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    _backdrop = [[UIVisualEffectView alloc] initWithEffect:blur];
    [self.view insertSubview:_backdrop atIndex:0];

    [self.tableView addObserver:self forKeyPath:NSStringFromSelector(@selector(contentSize)) options:NSKeyValueObservingOptionNew context:nil];

    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(selectRowForPan:)];
    [self.tableView addGestureRecognizer:_panGestureRecognizer];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    CGFloat boundsHeight = CGRectGetHeight(self.view.bounds);
    CGFloat contentHeight = self.tableView.contentSize.height;
    self.tableView.bounces = boundsHeight < contentHeight;

    CGSize preferred = CGSizeMake(250.0, contentHeight);
    self.preferredContentSize = preferred;

    self.panGestureRecognizer.enabled = contentHeight <= CGRectGetHeight(self.view.bounds);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _backdrop.frame = self.view.bounds;
}

- (void)dealloc {
    [self.tableView removeObserver:self forKeyPath:NSStringFromSelector(@selector(contentSize))];
}

- (CGSize)preferredContentSize {
    CGFloat height = self.tableView.contentSize.height;
    return CGSizeMake(250.0, height);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:NSStringFromSelector(@selector(contentSize))]) {
        CGSize newSize = [change[NSKeyValueChangeNewKey] CGSizeValue];
        self.preferredContentSize = CGSizeMake(250.0, newSize.height);

        CGFloat boundsHeight = CGRectGetHeight(self.view.bounds);
        self.tableView.bounces = boundsHeight < newSize.height;
        self.panGestureRecognizer.enabled = newSize.height <= boundsHeight;
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
        self.preferredContentSize = [self preferredContentSize];
    }];
}

#pragma mark - Pan gesture row selection

- (void)selectRowForPan:(UIPanGestureRecognizer *)recognizer {
    CGPoint location = [recognizer locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    UIGestureRecognizerState state = recognizer.state;

    if (state < UIGestureRecognizerStateEnded) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        UITableViewCellSelectionStyle selStyle = cell.selectionStyle;
        if (selStyle != UITableViewCellSelectionStyleNone && self.selectedPath != indexPath) {
            self.selectedPath = indexPath;
            [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
            UISelectionFeedbackGenerator *gen = [UISelectionFeedbackGenerator new];
            [gen prepare];
            [gen selectionChanged];
        } else if (self.selectedPath && (!indexPath || selStyle == UITableViewCellSelectionStyleNone)) {
            [self.tableView deselectRowAtIndexPath:self.selectedPath animated:NO];
            self.selectedPath = nil;
        }
    } else if (state == UIGestureRecognizerStateEnded) {
        [self tableView:self.tableView didSelectRowAtIndexPath:self.selectedPath];
        self.selectedPath = nil;
    } else if (state >= UIGestureRecognizerStateCancelled) {
        [self.tableView deselectRowAtIndexPath:self.selectedPath animated:NO];
        self.selectedPath = nil;
    }
}

#pragma mark - UITableViewDelegate overrides

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];

    NSString *text = cell.textLabel.text;
    if (!text || text.length == 0) {
        cell.backgroundColor = [UIColor dp_popoverSeparatorColor];
    } else {
        cell.backgroundColor = [UIColor clearColor];
    }

    NSArray *sections = self.data[@"sections"];
    NSDictionary *section = sections[indexPath.section];
    NSArray *rows = section[@"rows"];
    NSInteger lastRow = (NSInteger)rows.count - 1;

    if (indexPath.row == lastRow) {
        cell.separatorInset = UIEdgeInsetsMake(0, 10000, 0, 0);
        cell.indentationWidth = -10000;
        cell.indentationLevel = 1;
    } else {
        if (cell.separatorInset.left != 0.0 && cell.indentationWidth > 0.0) {
            cell.separatorInset = UIEdgeInsetsZero;
        }
    }

    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *rowData = [self dataForIndexPath:indexPath];
    id headerVal = rowData[@"header"];
    if (headerVal) {
        NSString *s = [self stringForDataValue:headerVal];
        return (s && s.length > 0) ? 30.0 : 8.0;
    }
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0.0;
}

@end
