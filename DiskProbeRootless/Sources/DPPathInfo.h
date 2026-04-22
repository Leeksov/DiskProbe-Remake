#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class UIViewController;

typedef NS_ENUM(NSInteger, DPPathInfoImageSource) {
    DPPathInfoImageSourceNone = 0,
    DPPathInfoImageSourceFile,
    DPPathInfoImageSourceApp,
};

@interface DPPathInfo : NSObject

@property (nonatomic, strong) NSURL *path;
@property (nonatomic, strong) NSURL *symbolicPath;
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, assign) unsigned long long bytes;
@property (nonatomic, copy)   NSString *size;
@property (nonatomic, copy, readonly) NSString *sizeLabel;
@property (nonatomic, strong) NSDate *modificationDate;
@property (nonatomic, copy)   NSString *modificationDateLabel;
@property (nonatomic, strong) NSDictionary *attributes;
@property (nonatomic, copy)   NSString *permissionsLabel;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, assign) BOOL isSymbolicLink;
@property (nonatomic, assign) BOOL isHidden;
@property (nonatomic, assign) BOOL isApplication;
@property (nonatomic, assign) BOOL isImage;
@property (nonatomic, copy)   NSString *applicationName;
@property (nonatomic, strong) NSDictionary *applicationBundle;

+ (instancetype)pathInfoWithURL:(NSURL *)url;
+ (instancetype)pathInfoWithURL:(NSURL *)url
                          bytes:(unsigned long long)bytes
                   modification:(NSDate *)modification
                       symbolic:(BOOL)symbolic
                         hidden:(BOOL)hidden;

- (NSString *)displayName;
- (UIImage *)displayImageWithSource:(DPPathInfoImageSource)source;
- (NSDictionary *)directoryInfo;
- (NSDictionary *)applicationInfo;
- (NSDictionary *)lsApplicationInfo;
- (NSDictionary *)urlInfo;
- (BOOL)isApplicationInstalled;
- (BOOL)removeItem;
- (BOOL)uninstallItem;
- (void)removeOrUninstallItem;
- (void)openInFilza;
- (UIViewController *)infoViewController;
- (UIViewController *)embeddedInfoViewController;
- (UIViewController *)previewController;
- (UIViewController *)embeddedPreviewController;

@end
