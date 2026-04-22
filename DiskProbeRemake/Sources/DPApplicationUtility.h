#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DPApplicationUtility : NSObject

+ (BOOL)uninstallApplicationWithIdentifier:(NSString *)bundleIdentifier;
+ (BOOL)installApplicationWithIdentifier:(NSString *)bundleIdentifier ipaPath:(NSString *)ipaPath;
+ (BOOL)applicationWithBundleIdentifierIsInstalled:(NSString *)bundleIdentifier;
+ (nullable NSDictionary *)applicationInfoForBundleIdentifier:(NSString *)bundleIdentifier;

@end

NS_ASSUME_NONNULL_END
