#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSFileManager (DP)

+ (BOOL)isDirectoryWithURL:(NSURL *)url;
+ (BOOL)isDirectoryWithPath:(NSString *)path;

+ (NSURL *)absolutePathForSymbolicURL:(NSURL *)url;
+ (NSString *)absolutePathForSymbolicPath:(NSString *)path;

+ (NSArray<NSString *> *)listItemsInDirectoryAtPath:(NSString *)path;
+ (NSArray<NSString *> *)listItemsInDirectoryAtPath:(NSString *)path deep:(BOOL)deep;

+ (NSArray<NSString *> *)listFilesInDirectoryAtPath:(NSString *)path;
+ (NSArray<NSString *> *)listFilesInDirectoryAtPath:(NSString *)path deep:(BOOL)deep;

+ (NSArray<NSString *> *)listDirectoriesInDirectoryAtPath:(NSString *)path;
+ (NSArray<NSString *> *)listDirectoriesInDirectoryAtPath:(NSString *)path deep:(BOOL)deep;

@end

NS_ASSUME_NONNULL_END
