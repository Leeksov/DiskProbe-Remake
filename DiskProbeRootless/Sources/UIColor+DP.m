#import "UIColor+DP.h"
#import "DPVersionCheck.h"

@implementation UIColor (DP)

+ (UIColor *)dp_labelColor {
    // iOS 13+: labelColor, else darkTextColor
    if (DPIsIOS13OrLater()) return [UIColor labelColor];
    return [UIColor darkTextColor];
}

+ (UIColor *)dp_secondaryLabelColor {
    // iOS 13+: secondaryLabelColor, else darkGrayColor
    if (DPIsIOS13OrLater()) return [UIColor secondaryLabelColor];
    return [UIColor darkGrayColor];
}

+ (UIColor *)dp_backgroundColor {
    // iOS 13+: systemBackgroundColor, else whiteColor
    if (DPIsIOS13OrLater()) return [UIColor systemBackgroundColor];
    return [UIColor whiteColor];
}

+ (UIColor *)dp_secondaryBackgroundColor {
    if (DPIsIOS13OrLater()) return [UIColor secondarySystemBackgroundColor];
    return [UIColor colorWithWhite:0.97 alpha:1.0];
}

+ (UIColor *)dp_foregroundColor {
    if (DPIsIOS13OrLater()) return [UIColor labelColor];
    return [UIColor blackColor];
}

+ (UIColor *)dp_tableCellBackgroundColor {
    if (DPIsIOS13OrLater()) return [UIColor secondarySystemBackgroundColor];
    return [UIColor whiteColor];
}

+ (UIColor *)dp_tableViewBackgroundColor {
    if (DPIsIOS13OrLater()) return [UIColor systemBackgroundColor];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIColor groupTableViewBackgroundColor];
#pragma clang diagnostic pop
}

+ (UIColor *)dp_tableViewGroupedBackgroundColor {
    if (DPIsIOS13OrLater()) return [UIColor systemGroupedBackgroundColor];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIColor groupTableViewBackgroundColor];
#pragma clang diagnostic pop
}

+ (UIColor *)dp_separatorColor {
    if (DPIsIOS13OrLater()) return [UIColor separatorColor];
    return [UIColor lightGrayColor];
}

+ (UIColor *)dp_separatorColorAlt {
    if (DPIsIOS13OrLater()) return [UIColor opaqueSeparatorColor];
    return [UIColor colorWithWhite:0.8 alpha:1.0];
}

+ (UIColor *)dp_popoverSeparatorColor {
    if (DPIsIOS13OrLater()) return [UIColor separatorColor];
    return [UIColor lightGrayColor];
}

+ (UIColor *)dp_lightBackgroundColor {
    return [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
}

+ (UIColor *)dp_darkBackgroundColor {
    return [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:1.0];
}

+ (UITraitCollection *)dp_traitCollectionWithInterfaceStyle:(UIUserInterfaceStyle)style
                                            interfaceLevel:(UIUserInterfaceLevel)level {
    if (@available(iOS 13.0, *)) {
        return [UITraitCollection traitCollectionWithTraitsFromCollections:@[
            [UITraitCollection traitCollectionWithUserInterfaceStyle:style],
            [UITraitCollection traitCollectionWithUserInterfaceLevel:level],
        ]];
    }
    return [UITraitCollection traitCollectionWithUserInterfaceIdiom:UIUserInterfaceIdiomPhone];
}

+ (UIColor *)dp_colorByEvaluatingHexString:(NSString *)hexString {
    NSString *hex = [hexString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    hex = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (hex.length == 3) {
        NSString *r = [hex substringWithRange:NSMakeRange(0, 1)];
        NSString *g = [hex substringWithRange:NSMakeRange(1, 1)];
        NSString *b = [hex substringWithRange:NSMakeRange(2, 1)];
        hex = [NSString stringWithFormat:@"%@%@%@%@%@%@", r, r, g, g, b, b];
    }
    unsigned int rgba = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&rgba];
    if (hex.length == 8) {
        return [UIColor colorWithRed:((rgba >> 24) & 0xFF) / 255.0
                               green:((rgba >> 16) & 0xFF) / 255.0
                                blue:((rgba >> 8) & 0xFF) / 255.0
                               alpha:(rgba & 0xFF) / 255.0];
    }
    return [UIColor colorWithRed:((rgba >> 16) & 0xFF) / 255.0
                           green:((rgba >> 8) & 0xFF) / 255.0
                            blue:(rgba & 0xFF) / 255.0
                           alpha:1.0];
}

+ (NSString *)dp_hexStringWithColor:(UIColor *)color format:(NSInteger)format {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    unsigned int ri = (unsigned int)(r * 255);
    unsigned int gi = (unsigned int)(g * 255);
    unsigned int bi = (unsigned int)(b * 255);
    unsigned int ai = (unsigned int)(a * 255);
    if (format == 1)
        return [NSString stringWithFormat:@"#%02X%02X%02X%02X", ri, gi, bi, ai];
    return [NSString stringWithFormat:@"#%02X%02X%02X", ri, gi, bi];
}

- (NSString *)dp_hexStringValue {
    return [UIColor dp_hexStringWithColor:self format:0];
}

- (UIColor *)dp_lerpToColor:(UIColor *)color withFraction:(CGFloat)fraction {
    return [UIColor dp_lerpColor:self toColor:color withFraction:fraction];
}

+ (UIColor *)dp_lerpColor:(UIColor *)from toColor:(UIColor *)to withFraction:(CGFloat)fraction {
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 0;
    CGFloat r2 = 0, g2 = 0, b2 = 0, a2 = 0;
    [from getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [to getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    return [UIColor colorWithRed:r1 + (r2 - r1) * fraction
                           green:g1 + (g2 - g1) * fraction
                            blue:b1 + (b2 - b1) * fraction
                           alpha:a1 + (a2 - a1) * fraction];
}

// Assigns a deterministic color to an object based on its hash
+ (UIColor *)dp_colorForObject:(id)object {
    static NSArray *palette;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        palette = @[
            [UIColor systemRedColor], [UIColor systemOrangeColor],
            [UIColor systemYellowColor], [UIColor systemGreenColor],
            [UIColor systemTealColor], [UIColor systemBlueColor],
            [UIColor systemIndigoColor], [UIColor systemPurpleColor],
            [UIColor systemPinkColor],
        ];
    });
    NSUInteger idx = [object hash] % palette.count;
    return palette[idx];
}

@end
