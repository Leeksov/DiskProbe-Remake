#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

@interface DPUserNotifications : NSObject

+ (instancetype)userNotificationCenter;

- (void)startNotificationCenter;
- (void)startNotificationCenterCompletion:(void (^)(BOOL granted))completion;

- (void)requestPushAuthorization:(void (^)(BOOL granted, NSError *error))completion;

- (void)removeNotificationWithIdentifier:(NSString *)identifier;
- (void)removeNotificationWithIdentifiers:(NSArray<NSString *> *)identifiers;
- (void)removeAllScheduled;
- (void)removeAllDelivered;
- (void)removeAllDeliveredAndScheduled;

- (void)schedulePushWithID:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                     sound:(UNNotificationSound *)sound
                   trigger:(UNNotificationTrigger *)trigger;

- (void)schedulePushWithID:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                   trigger:(UNNotificationTrigger *)trigger;

- (void)schedulePushWithID:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                     sound:(UNNotificationSound *)sound
                  interval:(NSTimeInterval)interval
                   repeats:(BOOL)repeats;

- (void)schedulePushWithID:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                  interval:(NSTimeInterval)interval
                   repeats:(BOOL)repeats;

- (void)schedulePushWithID:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                     sound:(UNNotificationSound *)sound
                      hour:(NSInteger)hour
                    minute:(NSInteger)minute
                   repeats:(BOOL)repeats;

- (void)schedulePushWithID:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                      hour:(NSInteger)hour
                    minute:(NSInteger)minute
                   repeats:(BOOL)repeats;

@end
