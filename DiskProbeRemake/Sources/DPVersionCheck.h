#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// sub_10008D41C(2, 13, 0, 0) — checks if running iOS >= 13.0
static inline BOOL DPIsIOS13OrLater(void) {
    if (@available(iOS 13.0, *)) return YES;
    return NO;
}
