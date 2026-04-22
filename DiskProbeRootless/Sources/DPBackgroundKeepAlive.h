#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DPBackgroundKeepAlive : NSObject

+ (instancetype)shared;

- (void)start;
- (void)stop;
- (BOOL)isActive;

@end

NS_ASSUME_NONNULL_END
