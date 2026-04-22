#import "DPSplitViewController.h"
#import <objc/message.h>

@implementation DPSplitViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.delegate = self;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    self.preferredDisplayMode = UISplitViewControllerDisplayModeAllVisible;
#pragma clang diagnostic pop
}

- (BOOL)splitViewController:(UISplitViewController *)splitViewController
    collapseSecondaryViewController:(UIViewController *)secondaryViewController
          ontoPrimaryViewController:(UIViewController *)primaryViewController {
    return YES;
}

- (UIViewController *)primaryViewControllerForExpandingSplitViewController:(UISplitViewController *)splitViewController {
    SEL selector = @selector(lastObject);
    UIDevice *device = [UIDevice currentDevice];
    if ([device respondsToSelector:@selector(userInterfaceIdiom)]) {
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            selector = @selector(firstObject);
        }
    }
    NSArray *viewControllers = self.viewControllers;
    return ((UIViewController *(*)(id, SEL))objc_msgSend)(viewControllers, selector);
}

- (UIViewController *)primaryViewControllerForCollapsingSplitViewController:(UISplitViewController *)splitViewController {
    return self.viewControllers.firstObject;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // Animation block executed alongside the transition.
    } completion:nil];
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (void)dismissSecondViewController {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UIViewController *blankController = [storyboard instantiateViewControllerWithIdentifier:@"BlankController"];
    UIViewController *primary = self.viewControllers.firstObject;
    self.viewControllers = @[primary, blankController];
    [blankController.navigationController popToRootViewControllerAnimated:NO];
}

@end
