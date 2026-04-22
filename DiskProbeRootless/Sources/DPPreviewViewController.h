#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <QuickLook/QuickLook.h>

@class DPPathInfo;
@class DPDocument;

NS_ASSUME_NONNULL_BEGIN

@interface DPPreviewViewController : UIViewController
    <WKNavigationDelegate,
     QLPreviewControllerDataSource,
     QLPreviewControllerDelegate>

@property (nonatomic, strong) DPPathInfo *info;
@property (nonatomic, strong, readonly) DPDocument *document;

@property (nonatomic, weak) IBOutlet UITextView *textView;
@property (nonatomic, weak) IBOutlet UIImageView *imageView;
@property (nonatomic, weak) IBOutlet WKWebView *webView;

@property (nonatomic, weak) IBOutlet UILabel *nameLabel;
@property (nonatomic, weak) IBOutlet UILabel *kindSizeLabel;
@property (nonatomic, weak) IBOutlet UILabel *kindLabel;
@property (nonatomic, weak) IBOutlet UILabel *sizeLabel;
@property (nonatomic, weak) IBOutlet UILabel *createdLabel;
@property (nonatomic, weak) IBOutlet UILabel *modifiedLabel;
@property (nonatomic, weak) IBOutlet UILabel *lastOpenLabel;
@property (nonatomic, weak) IBOutlet UILabel *whereLabel;

@property (nonatomic, weak) IBOutlet UIStackView *containerStack;
@property (nonatomic, weak) IBOutlet UIStackView *labelStack;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *imageViewTopConstraint;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *containerBottomAnchor;
@property (nonatomic, weak) IBOutlet UIView *labelStackContainer;
@property (nonatomic, weak) IBOutlet UILabel *miniTitleBarLabel;
@property (nonatomic, weak) IBOutlet UIView *miniTitleBarSeparator;
@property (nonatomic, weak) IBOutlet UIVisualEffectView *miniTitleBarBackgroundView;

+ (instancetype)previewControllerWithURL:(NSURL *)url;
+ (instancetype)previewControllerWithInfo:(DPPathInfo *)info;

- (void)dismiss;
- (void)openQuickLook;
- (void)toggleFullscreen;
- (void)setFullscreen:(BOOL)fullscreen animated:(BOOL)animated;
- (void)setMiniTitleLabelHidden:(BOOL)hidden;

- (NSString *)interfaceStyleScript;
- (void)insertCSSStringInto:(WKWebView *)webView;
- (void)updateAppearance;

- (void)imageViewTapped:(UITapGestureRecognizer *)gesture;
- (CGRect)contentClippingRectForImage:(UIImage *)image;

- (id)contextActionDataSourceForInfo:(DPPathInfo *)info;

@end

NS_ASSUME_NONNULL_END
