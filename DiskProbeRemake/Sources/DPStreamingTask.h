#import <Foundation/Foundation.h>

@class NSTask;

NS_ASSUME_NONNULL_BEGIN

typedef void (^DPStreamingTaskBlock)(NSString *chunk, NSString *completeOutput, BOOL finished, int terminationStatus);

@interface DPStreamingTask : NSObject

@property (nonatomic, strong, nullable) NSTask *task;
@property (nonatomic, copy, nullable) DPStreamingTaskBlock didUpdateBlock;
@property (nonatomic, strong, nullable) NSFileHandle *fileHandle;
@property (nonatomic, copy, nullable) NSString *availableOutput;
@property (nonatomic, copy, nullable) NSString *completeOutput;

+ (instancetype)streamingTaskForCommand:(NSString *)command didRecieveData:(DPStreamingTaskBlock)block;
+ (nullable NSString *)stringForFileHandle:(NSFileHandle *)fh;

- (void)runStreamingCommand:(NSString *)command didReceiveData:(DPStreamingTaskBlock)block;

@end

NS_ASSUME_NONNULL_END
