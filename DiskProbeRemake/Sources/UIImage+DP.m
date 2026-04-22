#import "UIImage+DP.h"
#import "DPVersionCheck.h"

@implementation UIImage (DP)

+ (UIImage *)dp_systemImageNamed:(NSString *)name {
    if (DPIsIOS13OrLater()) {
        UIImage *img = [UIImage systemImageNamed:name];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithScale:UIImageSymbolScaleLarge];
        return [img imageByApplyingSymbolConfiguration:config];
    }
    return [UIImage imageNamed:name];
}

- (UIImage *)dp_scaleImageToSize:(CGFloat)width :(CGFloat)height {
    CGSize size = CGSizeMake(width, height);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    [self drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return scaled;
}

@end
