#import "NSFileManager+DP.h"
#import <sys/stat.h>
#import <stdlib.h>

@implementation NSFileManager (DP)

+ (BOOL)isDirectoryWithURL:(NSURL *)url {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *resolved = [url URLByResolvingSymlinksInPath];
    BOOL isDir = NO;
    [fm fileExistsAtPath:[resolved path] isDirectory:&isDir];
    return isDir;
}

+ (BOOL)isDirectoryWithPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *resolved = [path stringByResolvingSymlinksInPath];
    BOOL isDir = NO;
    [fm fileExistsAtPath:resolved isDirectory:&isDir];
    return isDir;
}

+ (NSURL *)absolutePathForSymbolicURL:(NSURL *)url {
    struct stat st;
    lstat([[url path] UTF8String], &st);
    if ((st.st_mode & S_IFMT) != S_IFLNK) {
        return url;
    }
    char *resolved = realpath([[url path] UTF8String], NULL);
    if (!resolved) {
        return [url URLByStandardizingPath];
    }
    NSString *str = [NSString stringWithCString:resolved encoding:NSUTF8StringEncoding];
    NSURL *result = [NSURL fileURLWithPath:str];
    free(resolved);
    return result;
}

+ (NSString *)absolutePathForSymbolicPath:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path];
    return [[self absolutePathForSymbolicURL:url] path];
}

+ (NSArray<NSString *> *)listItemsInDirectoryAtPath:(NSString *)path {
    return [self listItemsInDirectoryAtPath:path deep:NO];
}

+ (NSArray<NSString *> *)listItemsInDirectoryAtPath:(NSString *)path deep:(BOOL)deep {
    if (![self isDirectoryWithPath:path]) {
        return @[path];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = deep
        ? [fm subpathsOfDirectoryAtPath:path error:NULL]
        : [fm contentsOfDirectoryAtPath:path error:NULL];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[contents count]];
    for (NSString *item in contents) {
        [result addObject:[path stringByAppendingPathComponent:item]];
    }
    return [result copy];
}

+ (NSArray<NSString *> *)listFilesInDirectoryAtPath:(NSString *)path {
    return [self listFilesInDirectoryAtPath:path deep:NO];
}

+ (NSArray<NSString *> *)listFilesInDirectoryAtPath:(NSString *)path deep:(BOOL)deep {
    NSArray *items = [self listItemsInDirectoryAtPath:path deep:deep];
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return ![self isDirectoryWithPath:evaluatedObject];
    }];
    return [items filteredArrayUsingPredicate:predicate];
}

+ (NSArray<NSString *> *)listDirectoriesInDirectoryAtPath:(NSString *)path {
    return [self listDirectoriesInDirectoryAtPath:path deep:NO];
}

+ (NSArray<NSString *> *)listDirectoriesInDirectoryAtPath:(NSString *)path deep:(BOOL)deep {
    NSArray *items = [self listItemsInDirectoryAtPath:path deep:deep];
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [self isDirectoryWithPath:evaluatedObject];
    }];
    return [items filteredArrayUsingPredicate:predicate];
}

@end
