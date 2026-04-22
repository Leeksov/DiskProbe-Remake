#import "DPAlert.h"
#import "DPAlertAction.h"

@interface DPAlert ()
@property (nonatomic, strong) UIAlertController *_controller;
@property (nonatomic, strong) NSMutableArray<DPAlertAction *> *_actions;
@property (nonatomic, strong) UITextField *_textField;
@property (nonatomic, copy) void (^_textFieldConfig)(UITextField *);
@end

@implementation DPAlert

- (instancetype)initWithController:(UIAlertController *)controller {
    self = [super init];
    if (self) {
        self._controller = controller;
        self._actions = [NSMutableArray array];
    }
    return self;
}

+ (void)showAlert:(NSString *)title message:(NSString *)message from:(UIViewController *)vc {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                             style:UIAlertActionStyleDefault
                                           handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

+ (UIAlertController *)make:(void (^)(DPAlert *))configure withStyle:(UIAlertControllerStyle)style {
    UIAlertController *controller = [UIAlertController alertControllerWithTitle:nil
                                                                        message:nil
                                                                 preferredStyle:style];
    DPAlert *builder = [[DPAlert alloc] initWithController:controller];
    if (configure) configure(builder);

    // Apply title/message
    if (builder.title) controller.title = builder.title();
    if (builder.message) controller.message = builder.message();

    // Add text field if configured
    if (builder._textFieldConfig) {
        [controller addTextFieldWithConfigurationHandler:builder._textFieldConfig];
        builder._textField = controller.textFields.firstObject;
    }

    // Add actions
    for (DPAlertAction *action in builder._actions) {
        UIAlertActionStyle astyle = UIAlertActionStyleDefault;
        if (action.destructiveStyle) astyle = UIAlertActionStyleDestructive;
        if (action.cancelStyle) astyle = UIAlertActionStyleCancel;
        UIAlertAction *uiAction = [UIAlertAction actionWithTitle:action.title
                                                           style:astyle
                                                         handler:^(UIAlertAction *a) {
            if (action.handler) action.handler(action);
        }];
        [controller addAction:uiAction];
    }
    return controller;
}

+ (void)makeAlert:(void (^)(DPAlert *))configure showFrom:(UIViewController *)vc {
    [self make:configure withStyle:UIAlertControllerStyleAlert showFrom:vc source:nil];
}

+ (void)makeSheet:(void (^)(DPAlert *))configure showFrom:(UIViewController *)vc {
    [self make:configure withStyle:UIAlertControllerStyleActionSheet showFrom:vc source:nil];
}

+ (void)makeSheet:(void (^)(DPAlert *))configure showFrom:(UIViewController *)vc source:(id)source {
    [self make:configure withStyle:UIAlertControllerStyleActionSheet showFrom:vc source:source];
}

+ (void)make:(void (^)(DPAlert *))configure withStyle:(UIAlertControllerStyle)style showFrom:(UIViewController *)vc source:(id)source {
    UIAlertController *controller = [self make:configure withStyle:style];
    // Configure popover for iPad
    if ([source isKindOfClass:[UIBarButtonItem class]]) {
        controller.popoverPresentationController.barButtonItem = source;
    } else if ([source isKindOfClass:[UIView class]]) {
        UIView *view = source;
        controller.popoverPresentationController.sourceView = view;
        controller.popoverPresentationController.sourceRect = view.bounds;
    }
    [vc presentViewController:controller animated:YES completion:nil];
}

#pragma mark - Builder methods

- (DPAlert *)title:(NSString *(^)(void))titleBlock {
    self.title = titleBlock;
    return self;
}

- (DPAlert *)message:(NSString *(^)(void))messageBlock {
    self.message = messageBlock;
    return self;
}

- (DPAlert *)button:(NSString *)title handler:(void (^)(void))handler {
    DPAlertAction *action = [DPAlertAction actionWithTitle:title handler:^(DPAlertAction *a) {
        if (handler) handler();
    }];
    [self._actions addObject:action];
    return self;
}

- (DPAlert *)destructiveButton:(NSString *)title handler:(void (^)(void))handler {
    DPAlertAction *action = [DPAlertAction destructiveActionWithTitle:title handler:^(DPAlertAction *a) {
        if (handler) handler();
    }];
    [self._actions addObject:action];
    return self;
}

- (DPAlert *)cancelButton {
    [self._actions addObject:[DPAlertAction cancelAction]];
    return self;
}

- (DPAlert *)textField:(void (^)(UITextField *))configure {
    self._textFieldConfig = configure;
    return self;
}

- (UITextField *)configuredTextField {
    return self._textField;
}

@end
