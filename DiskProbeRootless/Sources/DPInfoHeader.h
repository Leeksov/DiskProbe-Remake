#import <UIKit/UIKit.h>
#import "DPBarGraph.h"

@class DPInfoHeader;

@protocol DPInfoHeaderDelegate <NSObject, DPBarGraphDelegate>
@optional
- (void)handlePresentOptionsAlert:(id)sender;
@end

@interface DPInfoHeader : UICollectionReusableView

@property (nonatomic, weak) id<DPInfoHeaderDelegate> delegate;
@property (nonatomic, strong) DPBarGraph *graph;
@property (nonatomic, strong) UILabel *labelLeft;
@property (nonatomic, strong) UILabel *labelMiddle;
@property (nonatomic, strong) UILabel *labelRight;
@property (nonatomic, assign, getter=isAnimating) BOOL animating;

- (instancetype)initWithWidth:(CGFloat)width delegate:(id<DPInfoHeaderDelegate>)delegate info:(NSArray *)info;
- (UILabel *)newHeaderLabel;
- (void)setAttributedText:(NSAttributedString *)text label:(NSUInteger)labelIndex;

@end
