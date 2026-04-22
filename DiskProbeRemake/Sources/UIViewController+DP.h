#import <UIKit/UIKit.h>

@interface UIViewController (DP)

@property (nonatomic, weak) UIViewController *previewingContextParentController;
@property (nonatomic, strong) id previewingContext;

@property (nonatomic, readonly) UIViewController *contextController;

@end
