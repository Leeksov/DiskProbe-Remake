#import <UIKit/UIKit.h>

@interface DPAlertAction : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL destructiveStyle;
@property (nonatomic, assign) BOOL cancelStyle;
@property (nonatomic, copy) void (^handler)(DPAlertAction *action);
+ (instancetype)actionWithTitle:(NSString *)title handler:(void (^)(DPAlertAction *))handler;
+ (instancetype)destructiveActionWithTitle:(NSString *)title handler:(void (^)(DPAlertAction *))handler;
+ (instancetype)cancelAction;
@end
