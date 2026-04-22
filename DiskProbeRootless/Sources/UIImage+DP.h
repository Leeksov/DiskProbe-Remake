#import <UIKit/UIKit.h>

@interface UIImage (DP)
+ (UIImage *)dp_systemImageNamed:(NSString *)name;
- (UIImage *)dp_scaleImageToSize:(CGFloat)width :(CGFloat)height;
@end
