// DPReachability.m
// Ported 1:1 from DiskProbe binary.
// NOTE: Requires linking the SystemConfiguration framework (-framework SystemConfiguration).

#import "DPReachability.h"
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>

static void DPReachabilityCallback(SCNetworkReachabilityRef target,
                                   SCNetworkReachabilityFlags flags,
                                   void *info)
{
    DPReachability *reachability = (__bridge DPReachability *)info;
    @autoreleasepool {
        [reachability reachabilityChanged:flags];
    }
}

@implementation DPReachability

#pragma mark - Class constructors

+ (instancetype)reachabilityWithHostname:(NSString *)hostname
{
    SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithName(NULL, [hostname UTF8String]);
    if (ref) {
        return [[self alloc] initWithReachabilityRef:ref];
    }
    return nil;
}

+ (instancetype)reachabilityWithAddress:(void *)hostAddress
{
    SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault,
                                                                         (const struct sockaddr *)hostAddress);
    if (ref) {
        return [[self alloc] initWithReachabilityRef:ref];
    }
    return nil;
}

+ (instancetype)reachabilityForInternetConnection
{
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    return [self reachabilityWithAddress:&zeroAddress];
}

+ (instancetype)reachabilityForLocalWiFi
{
    struct sockaddr_in localWifiAddress;
    bzero(&localWifiAddress, sizeof(localWifiAddress));
    localWifiAddress.sin_len = sizeof(localWifiAddress);
    localWifiAddress.sin_family = AF_INET;
    // IN_LINKLOCALNETNUM = 169.254.0.0
    localWifiAddress.sin_addr.s_addr = htonl(IN_LINKLOCALNETNUM);
    return [self reachabilityWithAddress:&localWifiAddress];
}

+ (instancetype)reachabilityWithURL:(NSURL *)url
{
    NSString *host = [url host];
    if ([self isIpAddress:host]) {
        NSNumber *port = [url port];
        if (!port) {
            NSString *scheme = [url scheme];
            int portVal = [scheme isEqualToString:@"https"] ? 443 : 80;
            port = [NSNumber numberWithInt:portVal];
        }
        struct sockaddr_in address;
        bzero(&address, sizeof(address));
        address.sin_len = sizeof(address);
        address.sin_family = AF_INET;
        address.sin_port = htons([port intValue]);
        address.sin_addr.s_addr = inet_addr([host UTF8String]);
        return [self reachabilityWithAddress:&address];
    }
    return [self reachabilityWithHostname:host];
}

+ (BOOL)isIpAddress:(NSString *)host
{
    struct in_addr addr;
    return inet_aton([host UTF8String], &addr) == 1;
}

#pragma mark - Init/dealloc

- (instancetype)initWithReachabilityRef:(SCNetworkReachabilityRef)ref
{
    self = [super init];
    if (self) {
        self.reachableOnWWAN = YES;
        self.reachabilityRef = ref;
        self.reachabilitySerialQueue = dispatch_queue_create("com.creaturecoding.dpreachability", NULL);
    }
    return self;
}

- (void)dealloc
{
    [self stopNotifier];
    if (self.reachabilityRef) {
        CFRelease(self.reachabilityRef);
        self.reachabilityRef = NULL;
    }
    self.reachableBlock = nil;
    self.unreachableBlock = nil;
    self.reachabilityBlock = nil;
    self.reachabilitySerialQueue = nil;
}

#pragma mark - Notifier

- (BOOL)startNotifier
{
    if (self.reachabilityObject && self.reachabilityObject == self) {
        return YES;
    }

    SCNetworkReachabilityContext context = {0, (__bridge void *)self, NULL, NULL, NULL};

    if (SCNetworkReachabilitySetCallback(self.reachabilityRef, DPReachabilityCallback, &context)) {
        if (SCNetworkReachabilitySetDispatchQueue(self.reachabilityRef, self.reachabilitySerialQueue)) {
            self.reachabilityObject = self;
            return YES;
        }
        SCNetworkReachabilitySetCallback(self.reachabilityRef, NULL, NULL);
    }
    self.reachabilityObject = nil;
    return NO;
}

- (void)stopNotifier
{
    SCNetworkReachabilitySetCallback(self.reachabilityRef, NULL, NULL);
    SCNetworkReachabilitySetDispatchQueue(self.reachabilityRef, NULL);
    self.reachabilityObject = nil;
}

#pragma mark - Reachability tests

- (BOOL)isReachableWithFlags:(SCNetworkReachabilityFlags)flags
{
    // IDA: v3 = (~a3 & 5) != 0;   // bits 0 (TransientConnection) and 2 (ConnectionRequired)
    //      result = v3 & (a3 >> 1) & [reachableOnWWAN if IsWWAN]
    BOOL connectionUP = ((~flags & (kSCNetworkReachabilityFlagsTransientConnection |
                                    kSCNetworkReachabilityFlagsConnectionRequired)) != 0);
    BOOL isReachable = connectionUP && (((flags >> 1) & 1) != 0); // bit 1 = Reachable

    if (flags & kSCNetworkReachabilityFlagsIsWWAN) {
        isReachable = isReachable && self.reachableOnWWAN;
    }
    return isReachable;
}

- (BOOL)isReachable
{
    SCNetworkReachabilityFlags flags = 0;
    if (!SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags)) {
        return NO;
    }
    return [self isReachableWithFlags:flags];
}

- (BOOL)isReachableViaWWAN
{
    SCNetworkReachabilityFlags flags = 0;
    if (!SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags)) {
        return NO;
    }
    // (~flags & 0x40002) == 0  => both IsWWAN(0x40000) and Reachable(0x2) set
    return (~flags & (kSCNetworkReachabilityFlagsIsWWAN | kSCNetworkReachabilityFlagsReachable)) == 0;
}

- (BOOL)isReachableViaWiFi
{
    SCNetworkReachabilityFlags flags = 0;
    if (!SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags)) {
        return NO;
    }
    return (flags & kSCNetworkReachabilityFlagsReachable) != 0 &&
           (flags & kSCNetworkReachabilityFlagsIsWWAN) == 0;
}

- (BOOL)isConnectionRequired
{
    return [self connectionRequired];
}

- (BOOL)connectionRequired
{
    SCNetworkReachabilityFlags flags = 0;
    if (!SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags)) {
        return NO;
    }
    return (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
}

- (BOOL)isConnectionOnDemand
{
    SCNetworkReachabilityFlags flags = 0;
    if (!SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags)) {
        return NO;
    }
    // flags & 0x28 => ConnectionOnTraffic(0x8) | ConnectionOnDemand(0x20)
    return ((flags & (kSCNetworkReachabilityFlagsConnectionOnTraffic |
                      kSCNetworkReachabilityFlagsConnectionOnDemand)) != 0) &&
           ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
}

- (BOOL)isInterventionRequired
{
    SCNetworkReachabilityFlags flags = 0;
    if (!SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags)) {
        return NO;
    }
    // (~flags & 0x14) == 0 => both ConnectionRequired(0x4) and InterventionRequired(0x10) set
    return (~flags & (kSCNetworkReachabilityFlagsConnectionRequired |
                      kSCNetworkReachabilityFlagsInterventionRequired)) == 0;
}

#pragma mark - Status

- (DPNetworkStatus)currentReachabilityStatus
{
    if (![self isReachable]) {
        return DPNetworkStatusNotReachable;
    }
    if ([self isReachableViaWiFi]) {
        return DPNetworkStatusReachableViaWiFi;
    }
    return DPNetworkStatusReachableViaWWAN;
}

- (SCNetworkReachabilityFlags)reachabilityFlags
{
    SCNetworkReachabilityFlags flags = 0;
    if (SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags)) {
        return flags;
    }
    return 0;
}

- (NSString *)currentReachabilityString
{
    DPNetworkStatus status = [self currentReachabilityStatus];
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *key;
    if (status == DPNetworkStatusReachableViaWWAN) {
        key = @"Cellular";
    } else if (status == DPNetworkStatusReachableViaWiFi) {
        key = @"WiFi";
    } else {
        key = @"No Connection";
    }
    return [bundle localizedStringForKey:key value:@"" table:nil];
}

- (NSString *)currentReachabilityFlags
{
    SCNetworkReachabilityFlags flags = [self reachabilityFlags];

    // Matches IDA layout: "%c%c %c%c%c%c%c%c%c" with v4,v11,v10,v13,v14,v15,v16,v17,v18
    char wwan   = (flags & kSCNetworkReachabilityFlagsIsWWAN)               ? 'W' : '-'; // v4
    char reach  = (flags & kSCNetworkReachabilityFlagsReachable)            ? 'R' : '-'; // v11
    char cReq   = (flags & kSCNetworkReachabilityFlagsConnectionRequired)   ? 'c' : '-'; // v10
    char trans  = (flags & kSCNetworkReachabilityFlagsTransientConnection)  ? 't' : '-'; // v13
    char inter  = (flags & kSCNetworkReachabilityFlagsInterventionRequired) ? 'i' : '-'; // v14
    char cOnTr  = (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic)  ? 'C' : '-'; // v15
    char cOnDm  = (flags & kSCNetworkReachabilityFlagsConnectionOnDemand)   ? 'D' : '-'; // v16
    char local  = (flags & kSCNetworkReachabilityFlagsIsLocalAddress)       ? 'l' : '-'; // v17
    char direct = (flags & kSCNetworkReachabilityFlagsIsDirect)             ? 'd' : '-'; // v18

    return [NSString stringWithFormat:@"%c%c %c%c%c%c%c%c%c",
            wwan, reach, cReq, trans, inter, cOnTr, cOnDm, local, direct];
}

#pragma mark - Change notifications

- (void)reachabilityChanged:(SCNetworkReachabilityFlags)flags
{
    if ([self isReachableWithFlags:flags]) {
        if (self.reachableBlock) {
            self.reachableBlock(self);
        }
    } else {
        if (self.unreachableBlock) {
            self.unreachableBlock(self);
        }
    }

    if (self.reachabilityBlock) {
        self.reachabilityBlock(self, flags);
    }

    dispatch_block_t block = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"kDPReachabilityChangedNotification"
                                                            object:self];
    };

    if ([[NSThread currentThread] isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

#pragma mark - Description

- (NSString *)description
{
    NSString *className = NSStringFromClass([self class]);
    NSString *flagsString = [self currentReachabilityFlags];
    return [NSString stringWithFormat:@"<%@: %p (%@)>", className, self, flagsString];
}

@end
