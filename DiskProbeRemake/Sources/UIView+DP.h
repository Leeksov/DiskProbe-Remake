#import <UIKit/UIKit.h>

@interface UIView (DP)

- (UIView *)addTopBorderWithColor:(UIColor *)color andWidth:(CGFloat)width;
- (UIView *)addBottomBorderWithColor:(UIColor *)color andWidth:(CGFloat)width;
- (UIView *)addLeftBorderWithColor:(UIColor *)color andWidth:(CGFloat)width;
- (UIView *)addRightBorderWithColor:(UIColor *)color andWidth:(CGFloat)width;

@end
