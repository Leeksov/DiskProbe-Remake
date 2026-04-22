#import "DPContextAction.h"

@implementation DPContextAction

- (DPContextActionStringSetter)title {
    return ^DPContextAction *(NSString *value) {
        [self setTitleValue:value];
        return self;
    };
}

- (DPContextActionStringSetter)subTitle {
    return ^DPContextAction *(NSString *value) {
        [self setSubTitleValue:value];
        return self;
    };
}

- (DPContextActionImageSetter)image {
    return ^DPContextAction *(UIImage *value) {
        [self setImageValue:value];
        return self;
    };
}

- (DPContextActionBoolSetter)destructive {
    return ^DPContextAction *(BOOL value) {
        [self setDestructiveValue:value];
        return self;
    };
}

- (DPContextActionHandlerSetter)handler {
    return ^DPContextAction *(dispatch_block_t value) {
        [self setHandlerValue:value];
        return self;
    };
}

- (DPContextActionStringSetter)groupIdentifier {
    return ^DPContextAction *(NSString *value) {
        [self setGroupIdentifierValue:value];
        return self;
    };
}

- (DPContextActionStringSetter)groupTitle {
    return ^DPContextAction *(NSString *value) {
        [self setGroupTitleValue:value];
        return self;
    };
}

@end
