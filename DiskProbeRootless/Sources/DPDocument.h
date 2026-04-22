#import <UIKit/UIKit.h>

@interface DPDocument : UIDocument

@property (nonatomic, strong) NSString *stringValue;
@property (nonatomic, strong) UIImage *imageValue;

+ (BOOL)isBinaryPlistData:(NSData *)data;

@end
