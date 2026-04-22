#import "DPOperationQueue.h"

// SPI declarations for background operations
@interface NSOperationQueue (DPBackground)
- (BOOL)addBackgroundOperation:(NSOperation *)operation;
- (BOOL)addBackgroundOperationWithBlock:(void (^)(void))block;
@end

@implementation DPOperationQueue

+ (NSOperationQueue *)sharedQueue {
    static NSOperationQueue *sharedQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedQueue = [NSOperationQueue new];
        sharedQueue.maxConcurrentOperationCount = 1;
    });
    return sharedQueue;
}

+ (NSOperationQueue *)concurrentQueue {
    static NSOperationQueue *concurrentQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        concurrentQueue = [NSOperationQueue new];
        concurrentQueue.maxConcurrentOperationCount = 5;
    });
    return concurrentQueue;
}

+ (void)addTask:(NSOperation *)operation {
    [[self sharedQueue] addOperation:operation];
}

+ (BOOL)addBackgroundTask:(NSOperation *)operation {
    return [[self sharedQueue] addBackgroundOperation:operation];
}

+ (BOOL)addBackgroundTaskWithBlock:(void (^)(void))block {
    return [[self sharedQueue] addBackgroundOperationWithBlock:block];
}

+ (void)addConcurrentTask:(NSOperation *)operation {
    [[self concurrentQueue] addOperation:operation];
}

+ (BOOL)addConcurrentTaskWithBlock:(void (^)(void))block {
    [[self concurrentQueue] addOperationWithBlock:block];
    return YES;
}

+ (BOOL)addConcurrentBackgroundTask:(NSOperation *)operation {
    return [[self concurrentQueue] addBackgroundOperation:operation];
}

+ (BOOL)addConcurrentBackgroundTaskWithBlock:(void (^)(void))block {
    return [[self concurrentQueue] addBackgroundOperationWithBlock:block];
}

@end
