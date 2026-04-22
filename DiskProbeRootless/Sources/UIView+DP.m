#import "UIView+DP.h"

@implementation UIView (DP)

- (UIView *)addTopBorderWithColor:(UIColor *)color andWidth:(CGFloat)width {
    UIView *border = [UIView new];
    border.backgroundColor = color;
    border.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    border.frame = CGRectMake(0.0, 0.0, self.frame.size.width, width);
    [self addSubview:border];
    return border;
}

- (UIView *)addBottomBorderWithColor:(UIColor *)color andWidth:(CGFloat)width {
    UIView *border = [UIView new];
    border.backgroundColor = color;
    border.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    border.frame = CGRectMake(0.0, self.frame.size.height - width, self.frame.size.width, width);
    [self addSubview:border];
    return border;
}

- (UIView *)addLeftBorderWithColor:(UIColor *)color andWidth:(CGFloat)width {
    UIView *border = [UIView new];
    border.backgroundColor = color;
    border.frame = CGRectMake(0.0, 0.0, width, self.frame.size.height);
    border.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleRightMargin;
    [self addSubview:border];
    return border;
}

- (UIView *)addRightBorderWithColor:(UIColor *)color andWidth:(CGFloat)width {
    UIView *border = [UIView new];
    border.backgroundColor = color;
    border.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleLeftMargin;
    border.frame = CGRectMake(self.frame.size.width - width, 0.0, width, self.frame.size.height);
    [self addSubview:border];
    return border;
}

@end
