#import <UIKit/UIKit.h>

@class DPSplitViewController, DPPathViewController;

@interface DPAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) DPSplitViewController *splitViewController;
@property (nonatomic, weak) DPPathViewController *rootPathController;

- (void)navigateToURL:(NSURL *)url;
- (void)navigateToPath:(NSString *)path;

@end
