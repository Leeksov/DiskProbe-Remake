#import <UIKit/UIKit.h>

@class DPNavigationPathView;

@protocol DPNavigationPathViewDelegate <NSObject>
@optional
- (void)navigationViewWasTapped:(DPNavigationPathView *)view;
- (void)navigationViewDidExpandTextField:(UITextField *)textField;
- (void)navigationViewDidCollapseTextField:(UITextField *)textField;
- (void)navigationViewDidChangePath:(NSString *)path;
@end

@interface DPNavigationPathView : UIStackView <UITextFieldDelegate>

@property (nonatomic, weak) id<DPNavigationPathViewDelegate> delegate;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *indicator;
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, assign, getter=isActive) BOOL active;

- (instancetype)initWithTitle:(NSString *)title
                     delegate:(id<DPNavigationPathViewDelegate>)delegate
            forNavigationItem:(UINavigationItem *)navigationItem;

- (void)showTextFieldWithString:(NSString *)string;
- (void)hideTextField;
- (void)setTextFieldString:(NSString *)string;

@end
