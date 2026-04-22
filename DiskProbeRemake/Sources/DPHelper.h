#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface DPHelper : NSObject

+ (NSString *)displayStringForTimeInterval:(NSTimeInterval)interval;
+ (NSString *)displayStringForTimeInterval:(NSTimeInterval)interval style:(NSInteger)style;
+ (NSDateFormatter *)fileModificationDateFormatter;
+ (NSString *)displayStringForDate:(NSDate *)date;
+ (NSString *)displayStringForDate:(NSDate *)date style:(NSInteger)style;
+ (NSString *)permissionsStringForAttributes:(NSDictionary *)attributes;
+ (NSString *)mimeTypeForFile:(NSString *)path;
+ (CGFloat)screenScale;
+ (void)logMemoryPressure;
+ (void)writeDebugFiles;
+ (void)fixCachePermissions;

// Returns a display string for a given NSURLResource key/value pair
+ (id)displayValueForNSURLResourceKey:(NSString *)key inValue:(id)value;

// Rootless-aware size enumeration
+ (NSNumber *)sizeOfDirectory:(NSString *)path;
+ (NSNumber *)sizeOfDirectory:(NSString *)path dataSource:(NSMutableDictionary *)dataSource;

// Returns dict: dev-path -> mount-point (parsed from `df -h`)
+ (NSDictionary *)mountedVolumes;

// Returns human-readable size string
+ (NSString *)formatFileSize:(unsigned long long)bytes;

@end
