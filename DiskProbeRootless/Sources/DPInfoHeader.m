#import "DPInfoHeader.h"
#import "UIColor+DP.h"
#import "UIImage+DP.h"
#import "UIView+DP.h"

@interface DPInfoHeader ()
@property (nonatomic, strong) UIView *separator;
@property (nonatomic, strong) UIButton *filterButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinnerView;
@property (nonatomic, strong) UIStackView *stackH;
@property (nonatomic, strong) UIStackView *stackV;
@end

@implementation DPInfoHeader

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self _commonInit];
    }
    return self;
}

- (instancetype)initWithWidth:(CGFloat)width delegate:(id<DPInfoHeaderDelegate>)delegate info:(NSArray *)info {
    self = [super initWithFrame:CGRectMake(0, 0, width, 88.0)];
    if (self) {
        [self _commonInit];
        [self setDelegate:delegate];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(1.0, 88.0);
}

- (void)setDelegate:(id<DPInfoHeaderDelegate>)delegate {
    _delegate = delegate;
    [_filterButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [_filterButton addTarget:delegate
                      action:@selector(handlePresentOptionsAlert:)
            forControlEvents:UIControlEventTouchUpInside];
    _graph.delegate = (id<DPBarGraphDelegate>)delegate;
}

- (void)_commonInit {
    CGFloat width = CGRectGetWidth(self.frame);

    // Bottom separator via UIView+DP helper
    UIColor *sepColor = [UIColor dp_separatorColor];
    CGFloat sepWidth = 1.0 / [UIScreen mainScreen].scale;
    _separator = [self addBottomBorderWithColor:sepColor andWidth:sepWidth];
    _separator.translatesAutoresizingMaskIntoConstraints = NO;

    // DPBarGraph
    _graph = [[DPBarGraph alloc] initWithDelegate:nil];
    [_graph setFrame:CGRectMake(0, 0, width, 36.0)];

    // Filter button (hidden by default)
    _filterButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_filterButton setContentEdgeInsets:UIEdgeInsetsZero];
    [_filterButton setImageEdgeInsets:UIEdgeInsetsZero];
    [_filterButton setContentMode:UIViewContentModeScaleAspectFit];
    [_filterButton setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [_filterButton setContentVerticalAlignment:UIControlContentVerticalAlignmentTop];
    UIImage *filterIcon = [[UIImage dp_systemImageNamed:@"line.horizontal.3.decrease.circle"] dp_scaleImageToSize:25.0 :25.0];
    filterIcon = [filterIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [_filterButton setImage:filterIcon forState:UIControlStateNormal];
    _filterButton.hidden = YES;

    // Spinner
    _spinnerView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinnerView.color = [UIColor dp_secondaryLabelColor];
    _spinnerView.hidesWhenStopped = YES;
    _spinnerView.hidden = YES;

    // Spacer views
    UIView *spacerLeft = [UIView new];
    UIView *spacerRight = [UIView new];

    // Horizontal stack
    _stackH = [[UIStackView alloc] initWithFrame:CGRectMake(0, 0, width, 44.0)];
    _stackH.axis = UILayoutConstraintAxisHorizontal;
    _stackH.alignment = UIStackViewAlignmentFill;
    _stackH.distribution = UIStackViewDistributionEqualSpacing;

    // Vertical stack
    _stackV = [[UIStackView alloc] initWithFrame:CGRectMake(0, 0, width, 80.0)];
    _stackV.axis = UILayoutConstraintAxisVertical;
    _stackV.alignment = UIStackViewAlignmentFill;
    _stackV.distribution = UIStackViewDistributionFill;
    _stackV.layoutMarginsRelativeArrangement = YES;
    _stackV.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // Labels
    _labelLeft = [self newHeaderLabel];
    _labelMiddle = [self newHeaderLabel];
    _labelRight = [self newHeaderLabel];

    // [spacerLeft][spinner][labelLeft][labelMiddle][labelRight][filterButton][spacerRight]
    [_stackH addArrangedSubview:spacerLeft];
    [_stackH addArrangedSubview:_spinnerView];
    [_stackH addArrangedSubview:_labelLeft];
    [_stackH addArrangedSubview:_labelMiddle];
    [_stackH addArrangedSubview:_labelRight];
    [_stackH addArrangedSubview:_filterButton];
    [_stackH addArrangedSubview:spacerRight];

    [_stackV addArrangedSubview:_graph];
    [_stackV addArrangedSubview:_stackH];
    [self addSubview:_stackV];

    [NSLayoutConstraint activateConstraints:@[
        [_separator.leadingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.leadingAnchor],
        [_separator.trailingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.trailingAnchor],
        [_separator.heightAnchor constraintEqualToConstant:1.0 / [UIScreen mainScreen].scale],
        [_separator.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [spacerLeft.widthAnchor constraintEqualToConstant:16.0],
        [_filterButton.widthAnchor constraintEqualToConstant:25.0],
        [_filterButton.heightAnchor constraintEqualToConstant:25.0],
        [_spinnerView.widthAnchor constraintEqualToConstant:25.0],
        [_spinnerView.heightAnchor constraintEqualToConstant:25.0],
        [spacerRight.widthAnchor constraintEqualToConstant:16.0],
        [_stackH.heightAnchor constraintEqualToConstant:44.0],
    ]];
    [_filterButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
}

- (UILabel *)newHeaderLabel {
    UILabel *label = [UILabel new];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    label.textColor = [UIColor dp_secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

- (void)setAttributedText:(NSAttributedString *)text label:(NSUInteger)labelIndex {
    NSString *string = (NSString *)text;
    if (!string) {
        string = @"";
    }

    NSDictionary *baseAttrs = @{
        NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1],
        NSForegroundColorAttributeName: [UIColor dp_secondaryLabelColor],
    };
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:string attributes:baseAttrs];

    if ([string containsString:@"\n"]) {
        NSDictionary *secondaryAttrs = @{
            NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1],
            NSForegroundColorAttributeName: [UIColor dp_secondaryLabelColor],
        };
        NSRange nlRange = [string rangeOfString:@"\n"];
        NSString *tail = [string substringFromIndex:nlRange.location];
        NSRange tailRange = [string rangeOfString:tail];
        [attr setAttributes:secondaryAttrs range:tailRange];
    }

    UILabel *targetLabel = nil;
    switch (labelIndex) {
        case 0: targetLabel = _labelLeft; break;
        case 1: targetLabel = _labelMiddle; break;
        case 2: targetLabel = _labelRight; break;
        default: break;
    }
    targetLabel.attributedText = attr;
}

- (void)setAnimating:(BOOL)animating {
    _animating = animating;
    if (animating) {
        [_spinnerView startAnimating];
    } else {
        [_spinnerView stopAnimating];
    }
}

@end
