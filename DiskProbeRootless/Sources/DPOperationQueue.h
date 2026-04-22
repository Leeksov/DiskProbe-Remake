#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DPOperationQueue : NSObject

+ (NSOperationQueue *)sharedQueue;
+ (NSOperationQueue *)concurrentQueue;

+ (void)addTask:(NSOperation *)operation;
+ (BOOL)addBackgroundTask:(NSOperation *)operation;
+ (BOOL)addBackgroundTaskWithBlock:(void (^)(void))block;

+ (void)addConcurrentTask:(NSOperation *)operation;
+ (BOOL)addConcurrentTaskWithBlock:(void (^)(void))block;
+ (BOOL)addConcurrentBackgroundTask:(NSOperation *)operation;
+ (BOOL)addConcurrentBackgroundTaskWithBlock:(void (^)(void))block;

@end

NS_ASSUME_NONNULL_END
