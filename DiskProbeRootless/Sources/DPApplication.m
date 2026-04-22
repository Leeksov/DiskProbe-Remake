#import "DPApplication.h"
#import "DPUserPreferences.h"

@implementation DPApplication

- (UIContentSizeCategory)preferredContentSizeCategory {
    // 1:1 port: the original binary's DPUserPreferences -contentSize already
    // returns a UIContentSizeCategory NSString (indexed into a 12-element
    // table). When no override is set it is nil, so we fall back to the
    // system default.
    UIContentSizeCategory category = [[DPUserPreferences sharedPreferences] contentSize];
    if (category.length == 0) {
        return [super preferredContentSizeCategory];
    }
    return category;
}

@end
