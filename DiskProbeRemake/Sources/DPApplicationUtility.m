#import "DPApplicationUtility.h"
#import <objc/message.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

@implementation DPApplicationUtility

+ (BOOL)uninstallApplicationWithIdentifier:(NSString *)bundleIdentifier {
    if (!bundleIdentifier) {
        return NO;
    }

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        return NO;
    }

    id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
    if (!workspace) {
        return NO;
    }

    BOOL (*msgSend)(id, SEL, id, id) = (BOOL (*)(id, SEL, id, id))objc_msgSend;
    if (!msgSend(workspace, @selector(uninstallApplication:withOptions:), bundleIdentifier, nil)) {
        return NO;
    }

    return YES;
}

+ (BOOL)installApplicationWithIdentifier:(NSString *)bundleIdentifier ipaPath:(NSString *)ipaPath {
    if (!bundleIdentifier) {
        return NO;
    }

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        return NO;
    }

    id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
    if (!workspace) {
        return NO;
    }

    NSURL *ipaURL = [NSURL fileURLWithPath:ipaPath];
    NSDictionary *options = @{@"CFBundleIdentifier": bundleIdentifier};

    BOOL (*msgSend)(id, SEL, id, id) = (BOOL (*)(id, SEL, id, id))objc_msgSend;
    if (!msgSend(workspace, @selector(installApplication:withOptions:), ipaURL, options)) {
        return NO;
    }

    return YES;
}

+ (BOOL)applicationWithBundleIdentifierIsInstalled:(NSString *)bundleIdentifier {
    if (!bundleIdentifier) {
        return NO;
    }

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        return NO;
    }

    id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
    if (!workspace) {
        return NO;
    }

    BOOL (*msgSend)(id, SEL, id) = (BOOL (*)(id, SEL, id))objc_msgSend;
    if (!msgSend(workspace, @selector(applicationIsInstalled:), bundleIdentifier)) {
        return NO;
    }

    return YES;
}

+ (NSDictionary *)applicationInfoForBundleIdentifier:(NSString *)bundleIdentifier {
    if (!bundleIdentifier) {
        return nil;
    }

    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if (!proxyClass) {
        return nil;
    }

    id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleIdentifier];
    if (!proxy) {
        return nil;
    }

    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithCapacity:9];

    NSString *appID = [proxy performSelector:@selector(bundleIdentifier)];
    info[@"APP_ID"] = appID ?: @"???";

    NSURL *bundleContainerURL = [proxy performSelector:@selector(bundleContainerURL)];
    NSString *bundlePath = [bundleContainerURL path];
    info[@"BUNDLE_PATH"] = bundlePath ?: @"???";

    NSURL *bundleURL = [proxy performSelector:@selector(bundleURL)];
    NSString *appPath = [bundleURL path];
    info[@"APP_PATH"] = appPath ?: @"???";

    NSURL *dataContainerURL = [proxy performSelector:@selector(dataContainerURL)];
    NSString *dataPath = [dataContainerURL path];
    info[@"DATA_PATH"] = dataPath ?: @"???";

    NSString *version = [proxy performSelector:@selector(bundleVersion)];
    info[@"VERSION"] = version ?: @"???";

    NSString *shortVersion = [proxy performSelector:@selector(shortVersionString)];
    info[@"SHORT_VERSION"] = shortVersion ?: @"???";

    NSString *name = [proxy performSelector:@selector(localizedName)];
    info[@"NAME"] = name ?: @"???";

    NSString *displayName = [proxy performSelector:@selector(localizedShortName)];
    info[@"DISPLAY_NAME"] = displayName ?: @"???";

    NSURL *dataContainerURL2 = [proxy performSelector:@selector(dataContainerURL)];
    NSString *dataPath2 = [dataContainerURL2 path];
    info[@"DATA_PATH"] = dataPath2 ?: @"???";

    NSURL *dataContainerURL3 = [proxy performSelector:@selector(dataContainerURL)];
    NSString *containerPath = [dataContainerURL3 path];
    info[@"CONTAINER_PATH"] = containerPath ?: @"???";

    NSDictionary *env = [proxy performSelector:@selector(environmentVariables)];
    NSString *homePath = env[@"HOME"];
    info[@"HOME_PATH"] = homePath ?: @"???";

    NSDictionary *env2 = [proxy performSelector:@selector(environmentVariables)];
    NSString *envDescription = [env2 description];
    info[@"ENVIRONMENT"] = envDescription ?: @"???";

    return info;
}

@end

#pragma clang diagnostic pop
