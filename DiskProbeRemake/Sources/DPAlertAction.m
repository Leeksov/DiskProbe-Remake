#import "DPAlertAction.h"

@implementation DPAlertAction
+ (instancetype)actionWithTitle:(NSString *)title handler:(void (^)(DPAlertAction *))handler {
    DPAlertAction *a = [[DPAlertAction alloc] init];
    a.title = title;
    a.handler = handler;
    return a;
}
+ (instancetype)destructiveActionWithTitle:(NSString *)title handler:(void (^)(DPAlertAction *))handler {
    DPAlertAction *a = [self actionWithTitle:title handler:handler];
    a.destructiveStyle = YES;
    return a;
}
+ (instancetype)cancelAction {
    DPAlertAction *a = [[DPAlertAction alloc] init];
    a.title = NSLocalizedString(@"Cancel", nil);
    a.cancelStyle = YES;
    return a;
}
@end
