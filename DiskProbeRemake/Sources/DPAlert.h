#import <UIKit/UIKit.h>
#import "DPAlertAction.h"

@interface DPAlert : NSObject
@property (nonatomic, strong) NSString *(^title)(void);
@property (nonatomic, strong) NSString *(^message)(void);

+ (void)showAlert:(NSString *)title message:(NSString *)message from:(UIViewController *)vc;
+ (UIAlertController *)make:(void (^)(DPAlert *))configure withStyle:(UIAlertControllerStyle)style;
+ (void)makeAlert:(void (^)(DPAlert *))configure showFrom:(UIViewController *)vc;
+ (void)makeSheet:(void (^)(DPAlert *))configure showFrom:(UIViewController *)vc;
+ (void)makeSheet:(void (^)(DPAlert *))configure showFrom:(UIViewController *)vc source:(id)source;
+ (void)make:(void (^)(DPAlert *))configure withStyle:(UIAlertControllerStyle)style showFrom:(UIViewController *)vc source:(id)source;

- (DPAlert *)title:(NSString *(^)(void))titleBlock;
- (DPAlert *)message:(NSString *(^)(void))messageBlock;
- (DPAlert *)button:(NSString *)title handler:(void (^)(void))handler;
- (DPAlert *)destructiveButton:(NSString *)title handler:(void (^)(void))handler;
- (DPAlert *)cancelButton;
- (DPAlert *)textField:(void (^)(UITextField *))configure;
- (UITextField *)configuredTextField;
@end
