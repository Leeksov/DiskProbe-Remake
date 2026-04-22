#import "DPStreamingTask.h"

#ifdef ROOTLESS
#define DP_BASH_PATH @"/var/jb/bin/bash"
#else
#define DP_BASH_PATH @"/bin/bash"
#endif

// NSTask is SPI on iOS; declare the minimal selectors.
@interface NSTask : NSObject
- (instancetype)init;
- (void)setLaunchPath:(NSString *)path;
- (void)setArguments:(NSArray<NSString *> *)args;
- (void)setStandardOutput:(id)out;
- (void)setStandardError:(id)err;
- (void)launch;
- (void)waitUntilExit;
- (int)terminationStatus;
@end

@implementation DPStreamingTask

+ (instancetype)streamingTaskForCommand:(NSString *)command didRecieveData:(DPStreamingTaskBlock)block {
    DPStreamingTask *t = [DPStreamingTask new];
    [t runStreamingCommand:command didReceiveData:block];
    return t;
}

+ (NSString *)stringForFileHandle:(NSFileHandle *)fh {
    NSData *data = [fh availableData];
    if (data.length < 2) return nil;
    return [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
}

- (void)runStreamingCommand:(NSString *)command didReceiveData:(DPStreamingTaskBlock)block {
    _didUpdateBlock = [block copy];

    _task = [[NSTask alloc] init];
    [_task setLaunchPath:DP_BASH_PATH];
    [_task setArguments:@[@"-c", command]];

    NSPipe *pipe = [NSPipe pipe];
    [_task setStandardOutput:pipe];
    [_task setStandardError:pipe];

    _fileHandle = [pipe fileHandleForReading];
    [_fileHandle waitForDataInBackgroundAndNotify];

    __weak DPStreamingTask *weakSelf = self;
    id observer = [[NSNotificationCenter defaultCenter]
                    addObserverForName:NSFileHandleDataAvailableNotification
                                object:_fileHandle
                                 queue:nil
                            usingBlock:^(NSNotification *note) {
        DPStreamingTask *s = weakSelf;
        if (!s) return;

        NSString *chunk = [DPStreamingTask stringForFileHandle:s.fileHandle];
        s.availableOutput = chunk ?: @"";

        if (s.availableOutput.length > 0) {
            if (s.completeOutput) {
                s.completeOutput = [NSString stringWithFormat:@"%@\n%@", s.completeOutput, s.availableOutput];
            } else {
                s.completeOutput = s.availableOutput;
            }
            if (s.didUpdateBlock) {
                s.didUpdateBlock(s.availableOutput, s.completeOutput, NO, 1);
            }
        }
        [s.fileHandle waitForDataInBackgroundAndNotify];
    }];

    [_task launch];
    [_task waitUntilExit];

    [[NSNotificationCenter defaultCenter] removeObserver:observer];

    if (_didUpdateBlock) {
        _didUpdateBlock(@"", _completeOutput ?: @"", YES, [_task terminationStatus]);
    }
    _task = nil;
}

@end
