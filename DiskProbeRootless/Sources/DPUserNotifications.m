#import "DPUserNotifications.h"
#import <UIKit/UIKit.h>

@interface DPUserNotifications ()
@property (nonatomic, assign) BOOL authorized;
@end

@implementation DPUserNotifications

+ (instancetype)userNotificationCenter {
    static DPUserNotifications *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[DPUserNotifications alloc] init];
    });
    return sharedInstance;
}

- (void)startNotificationCenter {
    [self startNotificationCenterCompletion:nil];
}

- (void)startNotificationCenterCompletion:(void (^)(BOOL granted))completion {
    [self requestPushAuthorization:^(BOOL granted, NSError *error) {
        self.authorized = granted;
        if (error) {
            NSString *title = [[NSBundle mainBundle] localizedStringForKey:@"Notification Authorization Failed" value:@"" table:nil];
            [self _alertWithTitle:title message:[error localizedDescription]];
        }
        if (completion) {
            completion(granted);
        }
    }];
}

- (void)requestPushAuthorization:(void (^)(BOOL granted, NSError *error))completion {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert
                          completionHandler:completion];
}

- (void)removeNotificationWithIdentifier:(NSString *)identifier {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    NSArray *identifiers = [NSArray arrayWithObjects:&identifier count:1];
    [center removePendingNotificationRequestsWithIdentifiers:identifiers];
}

- (void)removeNotificationWithIdentifiers:(NSArray<NSString *> *)identifiers {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center removePendingNotificationRequestsWithIdentifiers:identifiers];
}

- (void)removeAllScheduled {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center removeAllPendingNotificationRequests];
}

- (void)removeAllDelivered {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center removeAllDeliveredNotifications];
}

- (void)removeAllDeliveredAndScheduled {
    [self removeAllDelivered];
    [self removeAllScheduled];
}

- (void)schedulePushWithID:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                     sound:(UNNotificationSound *)sound
                   trigger:(UNNotificationTrigger *)trigger {
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    [content setTitle:title];
    [content setSubtitle:subtitle];
    [content setSound:sound];

    NSString *requestID = identifier;
    if (!requestID) {
        requestID = [[NSUUID UUID] UUIDString];
    }

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:requestID
                                                                          content:content
                                                                          trigger:trigger];
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
    }];
}

- (void)schedulePushWithID:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                   trigger:(UNNotificationTrigger *)trigger {
    UNNotificationSound *sound = [UNNotificationSound defaultSound];
    [self schedulePushWithID:identifier title:title subtitle:subtitle sound:sound trigger:trigger];
}

- (void)schedulePushWithID:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                     sound:(UNNotificationSound *)sound
                  interval:(NSTimeInterval)interval
                   repeats:(BOOL)repeats {
    UNNotificationTrigger *trigger = [self _getTrigger:interval repeats:repeats];
    [self schedulePushWithID:identifier title:title subtitle:subtitle sound:sound trigger:trigger];
}

- (void)schedulePushWithID:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                  interval:(NSTimeInterval)interval
                   repeats:(BOOL)repeats {
    UNNotificationTrigger *trigger = [self _getTrigger:interval repeats:repeats];
    [self schedulePushWithID:identifier title:title subtitle:subtitle trigger:trigger];
}

- (void)schedulePushWithID:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                     sound:(UNNotificationSound *)sound
                      hour:(NSInteger)hour
                    minute:(NSInteger)minute
                   repeats:(BOOL)repeats {
    NSDateComponents *components = [NSDateComponents new];
    [components setHour:hour];
    [components setMinute:minute];
    UNCalendarNotificationTrigger *trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:components
                                                                                                     repeats:repeats];
    [self schedulePushWithID:identifier title:title subtitle:subtitle sound:sound trigger:trigger];
}

- (void)schedulePushWithID:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                      hour:(NSInteger)hour
                    minute:(NSInteger)minute
                   repeats:(BOOL)repeats {
    UNNotificationSound *sound = [UNNotificationSound defaultSound];
    [self schedulePushWithID:identifier
                       title:title
                    subtitle:subtitle
                       sound:sound
                        hour:hour
                      minute:minute
                     repeats:repeats];
}

- (UNNotificationTrigger *)_getTrigger:(NSTimeInterval)interval repeats:(BOOL)repeats {
    return [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:interval repeats:repeats];
}

- (void)_alertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    NSString *ok = [[NSBundle mainBundle] localizedStringForKey:@"OK" value:@"" table:nil];
    UIAlertAction *action = [UIAlertAction actionWithTitle:ok style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:action];

    UIApplication *app = [UIApplication sharedApplication];
    [[[[app delegate] window] rootViewController] presentViewController:alert animated:YES completion:nil];
}

@end
