#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DPUpdateChecker : NSObject

// Checks the GitHub Releases API for a newer tag than CFBundleShortVersionString.
// Throttles to at most one check per 24h. On new version, presents an alert on
// the app's root view controller.
+ (void)checkIfNeeded;

// Force a fresh check regardless of throttling.
+ (void)checkNow;

@end

NS_ASSUME_NONNULL_END
