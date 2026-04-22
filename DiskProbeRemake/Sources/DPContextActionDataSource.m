#import "DPContextActionDataSource.h"
#import "DPContextAction.h"

@interface DPContextActionDataSource ()
@property (nonatomic, strong, readwrite) NSMutableArray<DPContextAction *> *actions;
@end

@implementation DPContextActionDataSource

+ (instancetype)dataSourceWithBuilder:(DPContextActionDataSourceBuilder)builder {
    DPContextActionDataSource *dataSource = [DPContextActionDataSource new];
    builder(dataSource);
    return dataSource;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _actions = [NSMutableArray new];
    }
    return self;
}

- (DPContextAction *)action {
    DPContextAction *action = [DPContextAction new];
    action.groupIdentifier(@"_");
    [self.actions addObject:action];
    return action;
}

- (NSOrderedSet<NSString *> *)groupIdentifiers {
    NSArray *distinct = [self.actions valueForKeyPath:@"@distinctUnionOfObjects.groupIdentifierValue"];
    NSArray *sorted = [distinct sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return [NSOrderedSet orderedSetWithArray:sorted];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (NSArray<UIPreviewAction *> *)previewActionItems {
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:self.actions.count];
    [self.actions enumerateObjectsUsingBlock:^(DPContextAction *action, NSUInteger idx, BOOL *stop) {
        NSString *title = [action titleValue];
        UIPreviewActionStyle style = [action destructiveValue] ? UIPreviewActionStyleDestructive : UIPreviewActionStyleDefault;
        UIPreviewAction *item = [UIPreviewAction actionWithTitle:title
                                                           style:style
                                                         handler:^(UIPreviewAction * _Nonnull a, UIViewController * _Nonnull vc) {
            if ([action handlerValue]) {
                void (^handler)(void) = [action handlerValue];
                handler();
            }
        }];
        [items addObject:item];
    }];
    return items;
}
#pragma clang diagnostic pop

- (UIContextMenuActionProvider)actionProvider {
    NSMutableArray<UIMenu *> *menus = [NSMutableArray arrayWithCapacity:self.groupIdentifiers.count];
    NSArray *groupIds = [self.groupIdentifiers array];
    [groupIds enumerateObjectsUsingBlock:^(NSString *groupId, NSUInteger idx, BOOL *stop) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF.groupIdentifierValue == %@", groupId];
        NSArray *filtered = [self.actions filteredArrayUsingPredicate:predicate];
        if (filtered.count) {
            NSMutableArray<UIAction *> *children = [NSMutableArray arrayWithCapacity:filtered.count];
            [filtered enumerateObjectsUsingBlock:^(DPContextAction *action, NSUInteger idx2, BOOL *stop2) {
                NSString *title = [action titleValue];
                UIImage *image = [action imageValue];
                UIAction *uiAction = [UIAction actionWithTitle:title
                                                         image:image
                                                    identifier:nil
                                                       handler:^(__kindof UIAction * _Nonnull a) {
                    if ([action handlerValue]) {
                        void (^handler)(void) = [action handlerValue];
                        handler();
                    }
                }];
                [children addObject:uiAction];
            }];
            DPContextAction *first = filtered.firstObject;
            NSString *firstTitle = [first titleValue];
            NSString *firstGroupId = [first groupIdentifierValue];
            UIMenuOptions options = [first destructiveValue] ? UIMenuOptionsDestructive : UIMenuOptionsDisplayInline;
            UIMenu *menu = [UIMenu menuWithTitle:firstTitle
                                           image:nil
                                      identifier:firstGroupId
                                         options:options
                                        children:children];
            [menus addObject:menu];
        }
    }];
    return ^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        return [UIMenu menuWithTitle:@"" children:menus];
    };
}

@end
