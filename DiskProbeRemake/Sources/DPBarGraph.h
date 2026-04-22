#import <UIKit/UIKit.h>

@class DPBarGraph;

@protocol DPBarGraphDelegate <NSObject>
@optional
- (void)barGraph:(DPBarGraph *)graph didSelectSectionAtIndex:(NSInteger)index;
- (void)barGraph:(DPBarGraph *)graph didDeselectSection:(NSInteger)index;
@end

@interface DPBarGraph : UIView

@property (nonatomic, weak) id<DPBarGraphDelegate> delegate;
@property (nonatomic, strong) NSDictionary *dataSource;  // path -> NSNumber (bytes)
@property (nonatomic, copy) NSString *prompt;

- (instancetype)initWithDelegate:(id<DPBarGraphDelegate>)delegate;
- (void)setDataSourceIfChanged:(NSDictionary *)dataSource;
- (void)refreshInfo;
- (void)refreshInfoIfLayoutRequired;

@end
