#import <UIKit/UIKit.h>

@interface DPBarSection : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) unsigned long long bytes;
@property (nonatomic, assign) CGFloat ratio;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, strong) CALayer *layer;
@property (nonatomic, assign) CGFloat width;
@end
