#import <UIKit/UIKit.h>

@interface UIColor (DP)

+ (UIColor *)dp_labelColor;
+ (UIColor *)dp_secondaryLabelColor;
+ (UIColor *)dp_backgroundColor;
+ (UIColor *)dp_secondaryBackgroundColor;
+ (UIColor *)dp_foregroundColor;
+ (UIColor *)dp_tableCellBackgroundColor;
+ (UIColor *)dp_tableViewBackgroundColor;
+ (UIColor *)dp_tableViewGroupedBackgroundColor;
+ (UIColor *)dp_separatorColor;
+ (UIColor *)dp_separatorColorAlt;
+ (UIColor *)dp_popoverSeparatorColor;
+ (UIColor *)dp_lightBackgroundColor;
+ (UIColor *)dp_darkBackgroundColor;

+ (UIColor *)dp_colorByEvaluatingHexString:(NSString *)hexString;
+ (NSString *)dp_hexStringWithColor:(UIColor *)color format:(NSInteger)format;
- (NSString *)dp_hexStringValue;
- (UIColor *)dp_lerpToColor:(UIColor *)color withFraction:(CGFloat)fraction;
+ (UIColor *)dp_lerpColor:(UIColor *)from toColor:(UIColor *)to withFraction:(CGFloat)fraction;
+ (UIColor *)dp_colorForObject:(id)object;

+ (UITraitCollection *)dp_traitCollectionWithInterfaceStyle:(UIUserInterfaceStyle)style
                                            interfaceLevel:(UIUserInterfaceLevel)level;
@end
