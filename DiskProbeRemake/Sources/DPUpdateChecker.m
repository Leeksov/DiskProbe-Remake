#import "DPUpdateChecker.h"
#import <UIKit/UIKit.h>

static NSString *const kLastCheckKey = @"DPUpdateCheckerLastCheck";
static NSString *const kReleasesURL  = @"https://api.github.com/repos/Leeksov/DiskProbe-Remake/releases/latest";
static NSString *const kHumanURL     = @"https://github.com/Leeksov/DiskProbe-Remake/releases/latest";
static NSTimeInterval const kThrottle = 24 * 60 * 60;

@implementation DPUpdateChecker

+ (void)checkIfNeeded {
    NSDate *last = [[NSUserDefaults standardUserDefaults] objectForKey:kLastCheckKey];
    if (last && [[NSDate date] timeIntervalSinceDate:last] < kThrottle) return;
    [self checkNow];
}

+ (void)checkNow {
    NSURL *url = [NSURL URLWithString:kReleasesURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setTimeoutInterval:10];

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                     completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) return;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) return;

        NSString *latest = json[@"tag_name"];
        NSString *name   = json[@"name"];
        NSString *body   = json[@"body"];
        if (latest.length == 0) return;

        // Strip leading "v"
        NSString *latestClean = [latest hasPrefix:@"v"] ? [latest substringFromIndex:1] : latest;
        NSString *current = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if ([self _compareVersion:latestClean toVersion:current] != NSOrderedDescending) return;

        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kLastCheckKey];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *title = [NSString stringWithFormat:@"Update available — %@", name.length ? name : latest];
            NSString *msg = body.length ? body : [NSString stringWithFormat:@"Version %@ is available on GitHub.", latest];
            // Trim long bodies to keep the alert reasonable
            if (msg.length > 400) msg = [[msg substringToIndex:400] stringByAppendingString:@"…"];

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Open GitHub"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction *a) {
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:kHumanURL]
                                                  options:@{}
                                        completionHandler:nil];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];

            UIWindow *window = [UIApplication sharedApplication].delegate.window;
            UIViewController *root = window.rootViewController;
            while (root.presentedViewController) root = root.presentedViewController;
            [root presentViewController:alert animated:YES completion:nil];
        });
    }] resume];
}

// Semantic version compare. "1.2.10" > "1.2.9". Falls back to string compare
// if either side doesn't look numeric.
+ (NSComparisonResult)_compareVersion:(NSString *)a toVersion:(NSString *)b {
    NSArray<NSString *> *aParts = [a componentsSeparatedByString:@"."];
    NSArray<NSString *> *bParts = [b componentsSeparatedByString:@"."];
    NSUInteger n = MAX(aParts.count, bParts.count);
    for (NSUInteger i = 0; i < n; i++) {
        NSInteger ai = i < aParts.count ? [aParts[i] integerValue] : 0;
        NSInteger bi = i < bParts.count ? [bParts[i] integerValue] : 0;
        if (ai > bi) return NSOrderedDescending;
        if (ai < bi) return NSOrderedAscending;
    }
    return NSOrderedSame;
}

@end
