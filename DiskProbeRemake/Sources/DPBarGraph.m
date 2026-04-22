#import "DPBarGraph.h"
#import "DPBarSection.h"
#import "UIColor+DP.h"
#import "UIImage+DP.h"
#import "DPHelper.h"
#import "DPVersionCheck.h"

@interface DPBarGraph ()
@property (nonatomic, strong) UIView *flexibleContainer;
@property (nonatomic, strong) UIView *maskContainer;
@property (nonatomic, strong) UILabel *bar;
@property (nonatomic, strong) UIView *highlight;
@property (nonatomic, strong) NSMutableArray<DPBarSection *> *sections;
@property (nonatomic, assign) unsigned long long total;
@property (nonatomic, assign) BOOL blockedForPrompt;
@property (nonatomic, assign) BOOL layoutRequired;
@end

@implementation DPBarGraph

- (instancetype)initWithDelegate:(id<DPBarGraphDelegate>)delegate {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _delegate = delegate;
        _sections = [NSMutableArray array];
        [self _commonInit];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, 36.0);
}

- (void)_commonInit {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    // flexibleContainer — rounded background
    _flexibleContainer = [[UIView alloc] init];
    _flexibleContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _flexibleContainer.backgroundColor = [UIColor dp_secondaryBackgroundColor];
    _flexibleContainer.layer.cornerRadius = 9.0;
    _flexibleContainer.layer.masksToBounds = YES;
    if (DPIsIOS13OrLater()) {
        _flexibleContainer.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [self addSubview:_flexibleContainer];

    // maskContainer — inner rounded view
    _maskContainer = [[UIView alloc] init];
    _maskContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _maskContainer.layer.cornerRadius = 8.0;
    _maskContainer.layer.masksToBounds = YES;
    if (DPIsIOS13OrLater()) {
        _maskContainer.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [_flexibleContainer addSubview:_maskContainer];

    // bar label — shows text and holds gestures
    _bar = [[UILabel alloc] init];
    _bar.textAlignment = NSTextAlignmentCenter;
    _bar.textColor = [UIColor dp_secondaryLabelColor];
    _bar.translatesAutoresizingMaskIntoConstraints = NO;
    _bar.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    _bar.allowsDefaultTighteningForTruncation = YES;
    _bar.userInteractionEnabled = YES;
    _bar.numberOfLines = 0;
    [_maskContainer addSubview:_bar];

    // Constraints: flexibleContainer fills self with 4pt inset
    [NSLayoutConstraint activateConstraints:@[
        [_flexibleContainer.leadingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.leadingAnchor constant:4.0],
        [_flexibleContainer.trailingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.trailingAnchor constant:-4.0],
        [_flexibleContainer.topAnchor constraintEqualToAnchor:self.topAnchor constant:4.0],
        [_flexibleContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4.0],
        [_maskContainer.leadingAnchor constraintEqualToAnchor:_flexibleContainer.leadingAnchor constant:1.0],
        [_maskContainer.trailingAnchor constraintEqualToAnchor:_flexibleContainer.trailingAnchor constant:-1.0],
        [_maskContainer.topAnchor constraintEqualToAnchor:_flexibleContainer.topAnchor constant:1.0],
        [_maskContainer.bottomAnchor constraintEqualToAnchor:_flexibleContainer.bottomAnchor constant:-1.0],
        [_bar.leadingAnchor constraintEqualToAnchor:_maskContainer.leadingAnchor],
        [_bar.trailingAnchor constraintEqualToAnchor:_maskContainer.trailingAnchor],
        [_bar.topAnchor constraintEqualToAnchor:_maskContainer.topAnchor],
        [_bar.bottomAnchor constraintEqualToAnchor:_maskContainer.bottomAnchor],
    ]];

    // highlight overlay
    _highlight = [[UIView alloc] init];
    _highlight.alpha = 0.0;
    _highlight.userInteractionEnabled = NO;
    _highlight.translatesAutoresizingMaskIntoConstraints = NO;
    _highlight.backgroundColor = [[UIColor dp_secondaryBackgroundColor] colorWithAlphaComponent:0.4];

    // Gestures on bar
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handleGesture:)];
    pan.enabled = YES;
    pan.cancelsTouchesInView = NO;
    [_bar addGestureRecognizer:pan];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleGesture:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.enabled = YES;
    doubleTap.cancelsTouchesInView = NO;
    [_bar addGestureRecognizer:doubleTap];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_handleGesture:)];
    longPress.minimumPressDuration = 0.0;
    longPress.enabled = YES;
    longPress.cancelsTouchesInView = NO;
    [_bar addGestureRecognizer:longPress];
}

- (void)setPrompt:(NSString *)prompt {
    _prompt = [prompt copy];
    _blockedForPrompt = (prompt.length > 0);
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_bar.text = prompt;
        [self _updateRatios];
    });
}

- (void)setDataSourceIfChanged:(NSDictionary *)dataSource {
    if (_dataSource == dataSource || [_dataSource isEqualToDictionary:dataSource]) return;
    [self setDataSource:dataSource];
}

- (void)setDataSource:(NSDictionary *)dataSource {
    if (_blockedForPrompt) return;
    _total = 0;
    _dataSource = dataSource;
    _bar.text = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        [self _rebuildSections];
    });
}

- (void)_rebuildSections {
    NSMutableArray *newSections = [NSMutableArray array];
    unsigned long long total = 0;
    for (NSString *path in self->_dataSource) {
        unsigned long long bytes = [self->_dataSource[path] unsignedLongLongValue];
        total += bytes;
        DPBarSection *s = [[DPBarSection alloc] init];
        s.path = path;
        s.bytes = bytes;
        s.color = [UIColor dp_colorForObject:path];
        [newSections addObject:s];
    }
    self->_total = total;
    [newSections sortUsingComparator:^NSComparisonResult(DPBarSection *a, DPBarSection *b) {
        if (a.bytes > b.bytes) return NSOrderedAscending;
        if (a.bytes < b.bytes) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    // Remove sections that are too small (< 2% of total)
    [newSections filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DPBarSection *s, id __unused bindings) {
        return total == 0 || (double)s.bytes / total >= 0.02;
    }]];
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_sections = newSections;
        [self _updateRatios];
    });
}

- (void)_updateRatios {
    if (_total == 0) {
        // Still clear any stale section layers when we transition to empty
        [self refreshInfo];
        return;
    }
    for (DPBarSection *s in _sections) {
        s.ratio = (CGFloat)s.bytes / (CGFloat)_total;
    }
    _layoutRequired = YES;
    [self setNeedsLayout];
    [self refreshInfo];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self refreshInfo];
}

- (void)refreshInfo {
    CGFloat width = _maskContainer.bounds.size.width;
    CGFloat height = _maskContainer.bounds.size.height;
    if (width == 0 || height == 0) {
        _layoutRequired = YES;
        return;
    }

    // Remove ALL existing colored sublayers from maskContainer
    // (not just _sections' layers — those references may be stale across rebuilds)
    NSArray *existing = [_maskContainer.layer.sublayers copy];
    for (CALayer *sub in existing) {
        // Don't touch backing layers of subviews (like _bar)
        if ([sub isKindOfClass:[CALayer class]] && sub.delegate == nil) {
            [sub removeFromSuperlayer];
        }
    }

    CGFloat x = 0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (DPBarSection *s in _sections) {
        CGFloat w = s.ratio * width;
        if (w <= 0) continue;
        CALayer *layer = [CALayer layer];
        layer.frame = CGRectMake(x, 0, w, height);
        layer.backgroundColor = s.color.CGColor;
        [_maskContainer.layer addSublayer:layer];
        s.layer = layer;
        x += w;
    }
    [CATransaction commit];
    _layoutRequired = NO;
}

- (void)refreshInfoIfLayoutRequired {
    if (_layoutRequired) [self refreshInfo];
    _layoutRequired = NO;
}

- (void)_handleGesture:(UIGestureRecognizer *)gesture {
    if (!gesture) return;

    // Locate touch within the maskContainer and find the DPBarSection whose
    // layer frame contains that point.
    CGPoint pt = [gesture locationInView:_maskContainer];
    DPBarSection *hit = nil;
    for (DPBarSection *s in _sections) {
        if (s.layer && CGRectContainsPoint(s.layer.frame, pt)) {
            hit = s;
            break;
        }
    }
    if (!hit) {
        [self _setHighlight:nil completion:nil];
        return;
    }

    UIGestureRecognizerState state = gesture.state;

    if ([gesture isKindOfClass:[UIPanGestureRecognizer class]]) {
        // Pan: highlight while tracking; clear on cancelled/failed.
        if (state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateChanged) {
            [self _setHighlight:hit completion:nil];
        } else if (state == UIGestureRecognizerStateCancelled) {
            [self _setHighlight:nil completion:nil];
        } else if (state != UIGestureRecognizerStateFailed) {
            // Ended / other — fall through to release highlight.
            return;
        } else {
            [self _setHighlight:nil completion:nil];
        }
    } else if ([gesture isKindOfClass:[UITapGestureRecognizer class]]) {
        // Double-tap: on recognized, highlight and after animation clear, then show section prompt.
        if (state == UIGestureRecognizerStateEnded) {
            __weak __typeof(self) weakSelf = self;
            [self _setHighlight:hit completion:^{
                __strong __typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf _setHighlight:nil completion:nil];
            }];
            id delegate = self.delegate;
            if (delegate) {
                SEL showSel = NSSelectorFromString(@"showControllerForInfo:");
                if ([delegate respondsToSelector:showSel]) {
                    id info = nil;
                    SEL infoSel = NSSelectorFromString(@"info");
                    if ([hit respondsToSelector:infoSel]) {
                        IMP imp = [hit methodForSelector:infoSel];
                        id (*func)(id, SEL) = (id (*)(id, SEL))imp;
                        info = func(hit, infoSel);
                    }
                    IMP imp2 = [delegate methodForSelector:showSel];
                    void (*func2)(id, SEL, id) = (void (*)(id, SEL, id))imp2;
                    func2(delegate, showSel, info);
                }
            }
        } else if (state == UIGestureRecognizerStateBegan ||
                   state == UIGestureRecognizerStateChanged) {
            // Not produced by tap, but match IDA's branch table.
            [self _setHighlight:hit completion:nil];
        } else if (state == UIGestureRecognizerStateCancelled ||
                   state == UIGestureRecognizerStateFailed) {
            [self _setHighlight:nil completion:nil];
        }
    } else if ([gesture isKindOfClass:[UILongPressGestureRecognizer class]]) {
        // Long-press: highlight on began/changed; clear on cancelled/failed.
        if (state == UIGestureRecognizerStateBegan ||
            state == UIGestureRecognizerStateChanged) {
            [self _setHighlight:hit completion:nil];
        } else if (state == UIGestureRecognizerStateFailed ||
                   state == UIGestureRecognizerStateCancelled) {
            [self _setHighlight:nil completion:nil];
        }
    }
}

- (void)_setHighlight:(id)hit completion:(void (^)(void))completion {
    if (hit) {
        if (!_highlight.superview) {
            [_maskContainer addSubview:_highlight];
        }
        CGRect frame = CGRectZero;
        if ([hit isKindOfClass:[DPBarSection class]]) {
            DPBarSection *s = (DPBarSection *)hit;
            if (s.layer) frame = s.layer.frame;
        } else if ([hit isKindOfClass:[UIView class]]) {
            frame = [(UIView *)hit frame];
        }
        [UIView animateWithDuration:0.1
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            self->_highlight.frame = frame;
            self->_highlight.alpha = 1.0;
        } completion:^(BOOL finished) {
            if (completion) completion();
        }];
        id delegate = self.delegate;
        if (delegate) {
            SEL setTitleSel = NSSelectorFromString(@"setNavigationTitle:");
            if ([delegate respondsToSelector:setTitleSel]) {
                id info = nil;
                SEL infoSel = NSSelectorFromString(@"info");
                if ([hit respondsToSelector:infoSel]) {
                    IMP imp = [hit methodForSelector:infoSel];
                    id (*func)(id, SEL) = (id (*)(id, SEL))imp;
                    info = func(hit, infoSel);
                }
                NSString *displayName = nil;
                SEL dnSel = NSSelectorFromString(@"displayName");
                if ([info respondsToSelector:dnSel]) {
                    IMP imp = [info methodForSelector:dnSel];
                    id (*func)(id, SEL) = (id (*)(id, SEL))imp;
                    displayName = func(info, dnSel);
                }
                IMP imp2 = [delegate methodForSelector:setTitleSel];
                void (*func2)(id, SEL, id) = (void (*)(id, SEL, id))imp2;
                func2(delegate, setTitleSel, displayName);
            }
        }
    } else {
        [UIView animateWithDuration:0.1
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            self->_highlight.alpha = 0.0;
        } completion:^(BOOL finished) {
            [self->_highlight removeFromSuperview];
            if (completion) completion();
        }];
        id delegate = self.delegate;
        if (delegate) {
            SEL setTitleSel = NSSelectorFromString(@"setNavigationTitle:");
            if ([delegate respondsToSelector:setTitleSel]) {
                IMP imp = [delegate methodForSelector:setTitleSel];
                void (*func)(id, SEL, id) = (void (*)(id, SEL, id))imp;
                func(delegate, setTitleSel, nil);
            }
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    [self refreshInfo];
}

- (void)dealloc {
    for (DPBarSection *s in _sections) {
        [s.layer removeFromSuperlayer];
    }
}

@end
