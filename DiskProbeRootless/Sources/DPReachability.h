// DPReachability.h
// Ported 1:1 from DiskProbe binary.
// NOTE: Implementation requires linking the SystemConfiguration framework.

#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>

typedef NS_ENUM(NSInteger, DPNetworkStatus) {
    DPNetworkStatusNotReachable = 0,
    DPNetworkStatusReachableViaWWAN = 1,
    DPNetworkStatusReachableViaWiFi = 2,
};

@class DPReachability;

typedef void (^DPNetworkReachable)(DPReachability *reachability);
typedef void (^DPNetworkUnreachable)(DPReachability *reachability);
typedef void (^DPNetworkReachability)(DPReachability *reachability, SCNetworkReachabilityFlags flags);

@interface DPReachability : NSObject

@property (nonatomic, copy) DPNetworkReachable reachableBlock;
@property (nonatomic, copy) DPNetworkUnreachable unreachableBlock;
@property (nonatomic, copy) DPNetworkReachability reachabilityBlock;

@property (nonatomic, assign) BOOL reachableOnWWAN;
@property (nonatomic, assign) SCNetworkReachabilityRef reachabilityRef;
@property (nonatomic, strong) dispatch_queue_t reachabilitySerialQueue;
@property (nonatomic, strong) id reachabilityObject;

+ (instancetype)reachabilityWithHostname:(NSString *)hostname;
+ (instancetype)reachabilityWithAddress:(void *)hostAddress;
+ (instancetype)reachabilityForInternetConnection;
+ (instancetype)reachabilityForLocalWiFi;
+ (instancetype)reachabilityWithURL:(NSURL *)url;
+ (BOOL)isIpAddress:(NSString *)host;

- (instancetype)initWithReachabilityRef:(SCNetworkReachabilityRef)ref;

- (BOOL)startNotifier;
- (void)stopNotifier;

- (BOOL)isReachable;
- (BOOL)isReachableViaWWAN;
- (BOOL)isReachableViaWiFi;
- (BOOL)isConnectionRequired;
- (BOOL)connectionRequired;
- (BOOL)isConnectionOnDemand;
- (BOOL)isInterventionRequired;

- (DPNetworkStatus)currentReachabilityStatus;
- (SCNetworkReachabilityFlags)reachabilityFlags;
- (NSString *)currentReachabilityString;
- (NSString *)currentReachabilityFlags;

- (void)reachabilityChanged:(SCNetworkReachabilityFlags)flags;
- (BOOL)isReachableWithFlags:(SCNetworkReachabilityFlags)flags;

@end
