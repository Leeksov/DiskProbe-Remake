#import "UIViewController+DP.h"
#import <objc/runtime.h>

static const void *kPreviewingContextKey = &kPreviewingContextKey;
static const void *kPreviewingContextParentControllerKey = &kPreviewingContextParentControllerKey;

@implementation UIViewController (DP)

- (UIViewController *)previewingContextParentController {
    return objc_getAssociatedObject(self, kPreviewingContextParentControllerKey);
}

- (void)setPreviewingContextParentController:(UIViewController *)previewingContextParentController {
    objc_setAssociatedObject(self, kPreviewingContextParentControllerKey, previewingContextParentController, OBJC_ASSOCIATION_ASSIGN);
}

- (id)previewingContext {
    return objc_getAssociatedObject(self, kPreviewingContextKey);
}

- (void)setPreviewingContext:(id)previewingContext {
    objc_setAssociatedObject(self, kPreviewingContextKey, previewingContext, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIViewController *)contextController {
    UIViewController *parent = self.previewingContextParentController;
    if (!parent) {
        parent = self;
    }
    return parent;
}

@end
