#import "DPBackgroundKeepAlive.h"
#import <AVFoundation/AVFoundation.h>

@interface DPBackgroundKeepAlive ()
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *player;
@property (nonatomic, strong) AVAudioPCMBuffer *silentBuffer;
@property (nonatomic, assign) BOOL active;
@end

@implementation DPBackgroundKeepAlive

+ (instancetype)shared {
    static DPBackgroundKeepAlive *sInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[DPBackgroundKeepAlive alloc] init];
    });
    return sInstance;
}

- (instancetype)init {
    if ((self = [super init])) {
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(handleInterruption:)
                   name:AVAudioSessionInterruptionNotification
                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isActive {
    return self.active;
}

- (void)start {
    if (self.active) return;

    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryPlayback
                  withOptions:AVAudioSessionCategoryOptionMixWithOthers
                        error:&error]) {
        NSLog(@"[DPBackgroundKeepAlive] setCategory failed: %@", error);
        return;
    }
    if (![session setActive:YES error:&error]) {
        NSLog(@"[DPBackgroundKeepAlive] setActive failed: %@", error);
        return;
    }

    self.engine = [[AVAudioEngine alloc] init];
    self.player = [[AVAudioPlayerNode alloc] init];
    [self.engine attachNode:self.player];

    AVAudioFormat *format = [self.engine.mainMixerNode outputFormatForBus:0];
    [self.engine connect:self.player to:self.engine.mainMixerNode format:format];

    AVAudioPCMBuffer *buffer =
        [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:4096];
    buffer.frameLength = 4096;
    // Zero out channels (silent)
    AudioBufferList *abl = buffer.mutableAudioBufferList;
    for (UInt32 i = 0; i < abl->mNumberBuffers; i++) {
        memset(abl->mBuffers[i].mData, 0, abl->mBuffers[i].mDataByteSize);
    }
    self.silentBuffer = buffer;

    if (![self.engine startAndReturnError:&error]) {
        NSLog(@"[DPBackgroundKeepAlive] engine start failed: %@", error);
        return;
    }

    [self.player scheduleBuffer:buffer
                         atTime:nil
                        options:AVAudioPlayerNodeBufferLoops
              completionHandler:nil];
    [self.player play];

    self.active = YES;
}

- (void)stop {
    if (!self.active) return;

    [self.player stop];
    [self.engine stop];
    self.player = nil;
    self.engine = nil;
    self.silentBuffer = nil;

    NSError *error = nil;
    if (![[AVAudioSession sharedInstance]
            setActive:NO
          withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                error:&error]) {
        NSLog(@"[DPBackgroundKeepAlive] setActive:NO failed: %@", error);
    }

    self.active = NO;
}

- (void)handleInterruption:(NSNotification *)note {
    NSNumber *typeNum = note.userInfo[AVAudioSessionInterruptionTypeKey];
    if (!typeNum) return;
    AVAudioSessionInterruptionType type =
        (AVAudioSessionInterruptionType)typeNum.unsignedIntegerValue;

    if (type == AVAudioSessionInterruptionTypeBegan) {
        [self stop];
    } else if (type == AVAudioSessionInterruptionTypeEnded) {
        [self start];
    }
}

@end
