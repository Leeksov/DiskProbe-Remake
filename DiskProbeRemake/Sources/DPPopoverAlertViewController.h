#import "DPTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DPPopoverAlertViewController : DPTableViewController

@property (nonatomic, strong) UIVisualEffectView *backdrop;
@property (nonatomic, strong) UIPanGestureRecognizer *panGestureRecognizer;
@property (nonatomic, strong, nullable) NSIndexPath *selectedPath;

@end

NS_ASSUME_NONNULL_END
