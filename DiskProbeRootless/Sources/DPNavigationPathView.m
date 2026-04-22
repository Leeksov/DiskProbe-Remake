#import "DPNavigationPathView.h"
#import "UIColor+DP.h"
#import "UIImage+DP.h"
#import <objc/runtime.h>

@interface DPNavigationPathView ()
@property (nonatomic, weak) UINavigationItem *navigationItem;
@property (nonatomic, strong) NSArray<UIBarButtonItem *> *lastBarButtonItems;
@end

@implementation DPNavigationPathView

- (instancetype)init {
    self = [super init];
    if (self) {
        [self _init];
    }
    return self;
}

- (instancetype)initWithTitle:(NSString *)title
                     delegate:(id<DPNavigationPathViewDelegate>)delegate
            forNavigationItem:(UINavigationItem *)navigationItem {
    self = [super init];
    if (self) {
        self->_navigationItem = navigationItem;
        [self _init];
        [self setTitle:title];
        [self setDelegate:delegate];
    }
    return self;
}

- (void)_init {
    [self setUserInteractionEnabled:YES];
    [self setAxis:UILayoutConstraintAxisHorizontal];
    [self setAlignment:UIStackViewAlignmentFill];
    [self setDistribution:UIStackViewDistributionEqualSpacing];
    [self setSpacing:4.0];

    [self setTitleLabel:[UILabel new]];
    [[self titleLabel] setAllowsDefaultTighteningForTruncation:YES];
    [[self titleLabel] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [[self titleLabel] setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]];

    [self setIndicator:[UIImageView new]];
    [[self indicator] setContentMode:UIViewContentModeScaleAspectFit];
    [[self indicator] setTintColor:[UIColor dp_secondaryLabelColor]];
    [[self indicator] setImage:[UIImage dp_systemImageNamed:@"chevron.down"]];

    [self setTextField:[UITextField new]];
    [[self textField] setReturnKeyType:UIReturnKeyGo];
    [[self textField] setDelegate:self];
    [[self textField] setAutocorrectionType:UITextAutocorrectionTypeNo];
    [[self textField] addTarget:self
                         action:@selector(hideTextField)
               forControlEvents:UIControlEventEditingDidEndOnExit];

    [self hideTextField];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(_didTapNavigationView)];
    [self addGestureRecognizer:tap];

    [self addArrangedSubview:_titleLabel];
    [self addArrangedSubview:_textField];
    [self addArrangedSubview:_indicator];

    [[self titleLabel] setContentCompressionResistancePriority:999
                                                       forAxis:UILayoutConstraintAxisHorizontal];
    [[self indicator] setContentCompressionResistancePriority:1000
                                                      forAxis:UILayoutConstraintAxisHorizontal];
    [[self textField] setContentCompressionResistancePriority:250
                                                      forAxis:UILayoutConstraintAxisHorizontal];
    [[self titleLabel] setContentHuggingPriority:999
                                         forAxis:UILayoutConstraintAxisHorizontal];

    [[[self indicator] widthAnchor] constraintEqualToConstant:16.0].active = YES;

    [self setTranslatesAutoresizingMaskIntoConstraints:NO];
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    [[self titleLabel] setText:title];
}

- (void)showTextFieldWithString:(NSString *)string {
    [self setTextFieldString:string];
    [self setActive:YES];
}

- (void)hideTextField {
    [self setActive:NO];
}

- (void)setTextFieldString:(NSString *)string {
    [[self textField] setText:string];
}

- (void)setActive:(BOOL)active {
    if (active) {
        if (!_active) {
            [[self textField] setHidden:NO];
            [[self titleLabel] setHidden:YES];
            [[self indicator] setHidden:YES];
            [[self textField] becomeFirstResponder];
        }
    } else {
        if (_active) {
            [[self textField] resignFirstResponder];
            [[self textField] setHidden:YES];
            [[self titleLabel] setHidden:NO];
            [[self indicator] setHidden:NO];
            UINavigationItem *item = _navigationItem;
            [item setRightBarButtonItems:_lastBarButtonItems animated:YES];
        }
    }
    _active = active;
}

- (void)_didTapNavigationView {
    [[self delegate] navigationViewWasTapped:self];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self hideTextField];
    if ([self delegate]) {
        if ([[self delegate] respondsToSelector:@selector(navigationViewDidCollapseTextField:)]) {
            [[self delegate] navigationViewDidCollapseTextField:textField];
        }
        if ([[NSFileManager defaultManager] fileExistsAtPath:[textField text]]) {
            [[self delegate] navigationViewDidChangePath:[textField text]];
        }
    }
    return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    UINavigationItem *item = _navigationItem;
    [self setLastBarButtonItems:[item rightBarButtonItems]];

    NSString *cancelTitle = NSLocalizedString(@"Cancel", @"");
    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithTitle:cancelTitle
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(hideTextField)];
    [item setRightBarButtonItems:@[cancelItem] animated:YES];

    if ([[self delegate] respondsToSelector:@selector(navigationViewDidExpandTextField:)]) {
        [[self delegate] navigationViewDidExpandTextField:textField];
    }
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UILayoutFittingExpandedSize.width, CGRectGetHeight([self bounds]));
}

@end
