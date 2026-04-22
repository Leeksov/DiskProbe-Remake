#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class DPContextAction;

typedef DPContextAction *(^DPContextActionStringSetter)(NSString *value);
typedef DPContextAction *(^DPContextActionImageSetter)(UIImage *value);
typedef DPContextAction *(^DPContextActionBoolSetter)(BOOL value);
typedef DPContextAction *(^DPContextActionHandlerSetter)(dispatch_block_t handler);

@interface DPContextAction : NSObject

// Builder-style chainable setters. Each returns a block that stores the
// value on the corresponding *Value property and returns self.
@property (nonatomic, readonly) DPContextActionStringSetter  title;
@property (nonatomic, readonly) DPContextActionStringSetter  subTitle;
@property (nonatomic, readonly) DPContextActionImageSetter   image;
@property (nonatomic, readonly) DPContextActionBoolSetter    destructive;
@property (nonatomic, readonly) DPContextActionHandlerSetter handler;
@property (nonatomic, readonly) DPContextActionStringSetter  groupIdentifier;
@property (nonatomic, readonly) DPContextActionStringSetter  groupTitle;

// Underlying storage.
@property (nonatomic, copy)   NSString       *groupIdentifierValue;
@property (nonatomic, copy)   NSString       *groupTitleValue;
@property (nonatomic, copy)   NSString       *titleValue;
@property (nonatomic, copy)   NSString       *subTitleValue;
@property (nonatomic, strong) UIImage        *imageValue;
@property (nonatomic, assign) BOOL            destructiveValue;
@property (nonatomic, copy)   dispatch_block_t handlerValue;

@end
