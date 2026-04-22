#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class DPContextAction;
@class DPContextActionDataSource;

NS_ASSUME_NONNULL_BEGIN

typedef void (^DPContextActionDataSourceBuilder)(DPContextActionDataSource *dataSource);

@interface DPContextActionDataSource : NSObject

@property (nonatomic, strong, readonly) NSMutableArray<DPContextAction *> *actions;
@property (nonatomic, readonly) NSOrderedSet<NSString *> *groupIdentifiers;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
@property (nonatomic, readonly) NSArray<UIPreviewAction *> *previewActionItems;
#pragma clang diagnostic pop
@property (nonatomic, readonly) UIContextMenuActionProvider actionProvider;

+ (instancetype)dataSourceWithBuilder:(DPContextActionDataSourceBuilder)builder;

- (DPContextAction *)action;

@end

NS_ASSUME_NONNULL_END
