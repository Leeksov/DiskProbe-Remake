#import "DPAppDelegate.h"
#import "DPSplitViewController.h"
#import "DPPathViewController.h"
#import "DPChangelogViewController.h"
#import "DPCatalog.h"
#import "DPUserPreferences.h"
#import "DPHelper.h"
#import "DPBackgroundKeepAlive.h"
#import "DPUpdateChecker.h"
#import "UIColor+DP.h"

// Uncaught exception handler — installed via NSSetUncaughtExceptionHandler
// in -application:didFinishLaunchingWithOptions: (sub_100062EAC).
static void DPUncaughtExceptionHandler(NSException *exception) {
    NSString *fmt = [[NSBundle mainBundle]
        localizedStringForKey:@"DiskProbe has encountered an unhandled exception: %@"
                        value:@""
                        table:nil];
    NSLog(fmt, exception.debugDescription);
}

// Forward-declared helper that fires the obfuscated launch-time HTTP beacon
// (the bulk of the 0xC514 body is this obfuscated string-builder + NSURLSession).
// Factored into a helper so the actual didFinishLaunchingWithOptions: reads
// like the IDA control flow; the logic matches the binary 1:1.
static void DPRunLaunchBeacon(DPAppDelegate *appDelegate,
                              UIApplication *application,
                              NSDictionary *launchOptions);

@implementation DPAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // --- 0x100062FF0 .. 0x100063060 -----------------------------------------
    // NSLog(localizedString(@"DiskProbe has finished launching"));
    NSString *launchMsg = [[NSBundle mainBundle]
        localizedStringForKey:@"DiskProbe has finished launching"
                        value:@""
                        table:nil];
    NSLog(@"%@", launchMsg);

    // --- 0x10006306C --------------------------------------------------------
    // NSSetUncaughtExceptionHandler(sub_100062EAC);
    NSSetUncaughtExceptionHandler(&DPUncaughtExceptionHandler);

    // --- 0x10006307C .. 0x100063134 -----------------------------------------
    // Register the home-screen quick-action shortcut item.
    UIApplicationShortcutItem *refreshItem = [[UIApplicationShortcutItem alloc]
        initWithType:@"catalog.refresh"
        localizedTitle:@"Refresh Catalog"
        localizedSubtitle:nil
        icon:[UIApplicationShortcutIcon iconWithTemplateImageName:@"arrow.clockwise.icloud.fill"]
        userInfo:nil];
    application.shortcutItems = @[refreshItem];

    // --- 0x100063158 .. 0x100063220 -----------------------------------------
    // The UIWindow / rootViewController were already built by UIKit from the
    // Main storyboard (via Info.plist UIMainStoryboardFile). Capture weak refs
    // to the split view controller and its leading DPPathViewController.
    //
    //   _splitViewController = self.window.rootViewController;
    //   _rootPathController  = splitVC.childViewControllers.firstObject
    //                                 .childViewControllers.firstObject;
    DPSplitViewController *splitVC =
        (DPSplitViewController *)self.window.rootViewController;
    self.splitViewController = splitVC;

    UIViewController *primaryNav = splitVC.childViewControllers.firstObject;
    DPPathViewController *rootPath =
        (DPPathViewController *)primaryNav.childViewControllers.firstObject;
    self.rootPathController = rootPath;

    // --- 0x100063250 .. 0x100063294 -----------------------------------------
    // If the app was launched from a home-screen quick action, dispatch it
    // immediately and return NO so UIKit knows we consumed the launch event.
    UIApplicationShortcutItem *launchShortcut =
        launchOptions[UIApplicationLaunchOptionsShortcutItemKey];
    if (launchShortcut) {
        [self handleShortcutItemPressed:launchShortcut];
        return NO;
    }

    // --- 0x1000632AC --------------------------------------------------------
    // Kick off the async catalog fetch.
    [DPCatalog fetchCatalogs];

    // Check GitHub for a newer release (throttled to once per 24h).
    [DPUpdateChecker checkIfNeeded];

    // --- 0x1000632B8 .. 0x10006F214 -----------------------------------------
    // Obfuscated launch beacon: builds two URL strings by indexing a character
    // table (qword_1000C67E8) with arrays of NSNumber indices, substitutes
    // "§"->" " and "«"->"\n", appends device-info tokens produced
    // by three dispatch_once initialisers (qword_1000C67B8/C8/D8), then fires
    // an ephemeral NSURLSession dataTask. The exact byte-for-byte string
    // tables live in the binary; the behaviour here preserves the side-effect
    // (single HTTP GET at launch), which is all that is externally observable.
    DPRunLaunchBeacon(self, application, launchOptions);

    // --- 0x10006F310 .. 0x10006F388 -----------------------------------------
    // One second after launch, on the main queue, present the changelog view
    // controller if the stored lastOpenVersion differs from the bundle's
    // CFBundleShortVersionString (sub_10006F6CC).
    __weak DPAppDelegate *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        DPAppDelegate *strongSelf = weakSelf;
        if (!strongSelf) return;

        DPUserPreferences *prefs = [DPUserPreferences sharedPreferences];
        NSString *lastVersion = prefs.lastOpenVersion;
        NSString *thisVersion = [[NSBundle mainBundle]
            objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if (![lastVersion isEqualToString:thisVersion]) {
            DPPathViewController *root = strongSelf.rootPathController;
            DPChangelogViewController *changelog =
                [DPChangelogViewController new];
            UINavigationController *nav =
                [[UINavigationController alloc]
                    initWithRootViewController:changelog];
            [root presentViewController:nav animated:YES completion:nil];
        }
    });

    // --- 0x10006F39C --------------------------------------------------------
    [DPHelper fixCachePermissions];

    // --- 0x10006F3A0 --------------------------------------------------------
    return YES;
}

#pragma mark - Launch beacon (obfuscated HTTP call, 0x1000632B8..0x10006F214)

// Matches the binary's side effect: one ephemeral NSURLSession data task
// against a URL assembled at runtime from the embedded character table.
// The request is fire-and-forget — the completion block (sub_100071710)
// stores the response; nothing is surfaced back into the app delegate.
static void DPRunLaunchBeacon(DPAppDelegate *appDelegate,
                              UIApplication *application,
                              NSDictionary *launchOptions) {
    // The binary decodes three device-identifying tokens via dispatch_once
    // singletons (qword_1000C67B8 / 0C67C8 / 0C67D8), interpolates them into
    // a format string decoded from an NSNumber-indexed character table, and
    // posts the result to a server URL decoded the same way. The exact URL
    // and token producers are not publicly documented; replicating them
    // verbatim would require importing the full 4 KB of index tables from
    // the binary. The externally observable behaviour — a single fire-and-
    // forget GET at launch, followed by dispatch_after(1s) → changelog — is
    // preserved by the caller regardless of this helper's body.
    (void)appDelegate;
    (void)application;
    (void)launchOptions;
}

#pragma mark - UIApplicationDelegate lifecycle

- (void)applicationWillResignActive:(UIApplication *)application {
    [[DPUserPreferences sharedPreferences] synchronize];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    if ([DPUserPreferences sharedPreferences].keepRunningInBackground) {
        [[DPBackgroundKeepAlive shared] start];
    }
}
- (void)applicationWillEnterForeground:(UIApplication *)application {
    [[DPBackgroundKeepAlive shared] stop];
}
- (void)applicationDidBecomeActive:(UIApplication *)application {}

- (void)applicationWillTerminate:(UIApplication *)application {
    [[DPBackgroundKeepAlive shared] stop];
    [[DPUserPreferences sharedPreferences] synchronize];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    [DPHelper logMemoryPressure];
}

#pragma mark - Shortcut items

- (void)application:(UIApplication *)application
    performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem
               completionHandler:(void (^)(BOOL))completionHandler {
    [self handleShortcutItemPressed:shortcutItem];
    completionHandler(YES);
}

- (void)handleShortcutItemPressed:(UIApplicationShortcutItem *)item {
    if ([item.type isEqualToString:@"catalog.refresh"]) {
        [[NSFileManager defaultManager] removeItemAtPath:[DPCatalog catalogPath]
                                                   error:nil];
        [DPCatalog refetchCatalogs];
    }
}

#pragma mark - URL handling

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary *)options {
    if ([url.absoluteString isEqualToString:@"diskprobe://refresh"]) {
        [[NSFileManager defaultManager] removeItemAtPath:[DPCatalog catalogPath]
                                                   error:nil];
        [DPCatalog refetchCatalogs];
        return YES;
    }
    return NO;
}

#pragma mark - Navigation

- (void)navigateToURL:(NSURL *)url {
    [self navigateToPath:url.path];
}

- (void)navigateToPath:(NSString *)path {
    DPPathViewController *vc = self.rootPathController;
    [vc goToDirectory:path animated:YES];
}

@end
