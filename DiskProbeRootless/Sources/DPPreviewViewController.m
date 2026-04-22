#import "DPPreviewViewController.h"
#import "DPPathInfo.h"
#import "DPDocument.h"
#import "DPHelper.h"
#import "DPContextActionDataSource.h"
#import "DPContextAction.h"
#import "UIImage+DP.h"
#import "UIColor+DP.h"
#import "UIViewController+DP.h"

@interface DPPreviewViewController ()
{
    BOOL _isFullscreen;
    BOOL _isDarkStyleImageView;
    BOOL _isDocumentLoaded;
    DPDocument *_document;
    DPPathInfo *_info;
    NSArray<UILabel *> *_infoLabelTitles;
    UIBarButtonItem *_quickLookItem;
    UIBarButtonItem *_fullScreenItem;
    UIBarButtonItem *_minimizeItem;
}
@end

// Helper for UIView addBottomBorderWithColor:andWidth:
// (assumed available via a project-wide UIView category as referenced by IDA)
@interface UIView (DPBottomBorder)
- (id)addBottomBorderWithColor:(UIColor *)color andWidth:(CGFloat)width;
@end

@implementation DPPreviewViewController

@synthesize info = _info;
@synthesize document = _document;

+ (instancetype)previewControllerWithURL:(NSURL *)url {
    DPPathInfo *info = [DPPathInfo pathInfoWithURL:url];
    return [self previewControllerWithInfo:info];
}

+ (instancetype)previewControllerWithInfo:(DPPathInfo *)info {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    NSString *identifier = NSStringFromClass([self class]);
    DPPreviewViewController *vc = [storyboard instantiateViewControllerWithIdentifier:identifier];
    [vc setInfo:info];
    return vc;
}

- (void)awakeFromNib {
    [super awakeFromNib];

    _fullScreenItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage dp_systemImageNamed:@"arrow.up.left.and.arrow.down.right"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(toggleFullscreen)];

    _minimizeItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage dp_systemImageNamed:@"arrow.down.right.and.arrow.up.left"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(toggleFullscreen)];

    _quickLookItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage dp_systemImageNamed:@"eye.fill"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(openQuickLook)];

    [self setFullscreen:NO animated:NO];
}

- (UIModalPresentationStyle)modalPresentationStyle {
    return UIModalPresentationFormSheet;
}

- (void)setInfo:(DPPathInfo *)info {
    _info = info;
    _document = [[DPDocument alloc] initWithFileURL:info.symbolicPath];
}

- (DPPathInfo *)info {
    return _info;
}

- (DPDocument *)document {
    return _document;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // 1px separator under mini title bar
    CGFloat scale = [[UIScreen mainScreen] scale];
    [[self.miniTitleBarSeparator.heightAnchor constraintEqualToConstant:1.0 / scale] setActive:YES];
    self.miniTitleBarSeparator.backgroundColor = [UIColor dp_separatorColor];

    UIBlurEffect *blur = nil;
    if (@available(iOS 13.0, *)) {
        blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
    } else {
        blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    }
    self.miniTitleBarBackgroundView.effect = blur;

    self.webView.hidden = YES;
    self.imageView.hidden = YES;
    self.textView.hidden = YES;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(dismiss)];
    self.navigationItem.rightBarButtonItems = @[_quickLookItem, _fullScreenItem];

    self.title = @"Preview";

    CGRect navFrame = self.navigationController.navigationBar.frame;
    self.imageViewTopConstraint.constant = CGRectGetHeight(navFrame) + 8.0;

    self.webView.navigationDelegate = self;

    WKUserScript *script = [[WKUserScript alloc] initWithSource:[self interfaceStyleScript]
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES];
    [self.webView.configuration.userContentController addUserScript:script];

    UIColor *bgColor = self.view.backgroundColor;
    UIColor *resolved;
    if (_isDarkStyleImageView) {
        UIColor *white = [UIColor whiteColor];
        if (@available(iOS 13.0, *)) {
            UITraitCollection *trait = [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight];
            resolved = [bgColor resolvedColorWithTraitCollection:trait];
        } else {
            resolved = white;
        }
    } else {
        UIColor *black = [UIColor blackColor];
        if (@available(iOS 13.0, *)) {
            UITraitCollection *trait = [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark];
            resolved = [bgColor resolvedColorWithTraitCollection:trait];
        } else {
            resolved = black;
        }
    }
    self.imageView.backgroundColor = resolved;

    // Add bottom borders to each label stack row
    for (UIView *row in self.labelStack.arrangedSubviews) {
        [row addBottomBorderWithColor:[UIColor dp_separatorColor]
                             andWidth:1.0 / [DPHelper screenScale]];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    id parent = [self previewingContextParentController];
    if (parent) {
        [self setFullscreen:YES animated:NO];
        self.miniTitleBarLabel.text = [self.info displayName];
        [self setMiniTitleLabelHidden:NO];
    } else {
        [self setMiniTitleLabelHidden:YES];
        [self setFullscreen:_isFullscreen animated:NO];
    }

    if (!_isDocumentLoaded && _document && _info) {
        __weak DPPreviewViewController *weakSelf = self;
        void (^onLoaded)(void) = ^{
            DPPreviewViewController *self2 = weakSelf;
            if (!self2) return;

            // Known types that render through the WKWebView
            NSArray<NSString *> *webTypes = @[
                @"gif", @"pdf", @"svg",
                @"3gp", @"3gpp", @"3g2", @"3gp2",
                @"aiff", @"aif", @"aifc", @"cdda",
                @"amr", @"mp3", @"swa",
                @"mp4", @"mpeg", @"mpg", @"mp3",
                @"wav", @"bwf",
                @"m4a", @"m4b", @"m4p",
                @"mov", @"qt", @"mqv", @"m4v",
                @"js", @"css", @"html", @"htm",
                @"ttf", @"woff", @"eot", @"woff2",
                @"javascript",
            ];
            BOOL isWebType = NO;
            NSString *fileType = [[(id)self2->_info fileType] lowercaseString];
            for (NSString *ext in webTypes) {
                if ([fileType containsString:ext]) {
                    isWebType = YES;
                    break;
                }
            }

            if (isWebType) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSURL *fileURL = [(id)self2->_info symbolicPath];
                    NSURL *readAccessURL = [fileURL URLByDeletingLastPathComponent];
                    [self2.webView loadFileURL:fileURL allowingReadAccessToURL:readAccessURL];
                    self2.webView.hidden = NO;
                    self2.textView.hidden = YES;
                    self2.imageView.hidden = YES;
                });
            } else {
                [self2->_document openWithCompletionHandler:^(BOOL success) {
                    if (self2->_document.stringValue) {
                        NSString *text = self2->_document.stringValue;
                        NSUInteger length = self2.textView.text.length;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self2.textView.text = text;
                            self2.textView.hidden = NO;
                            self2.webView.hidden = YES;
                            self2.imageView.hidden = YES;
                            [self2.textView.layoutManager
                                ensureLayoutForCharacterRange:NSMakeRange(0, length)];
                        });
                    } else if (self2->_document.imageValue) {
                        UIImage *image = self2->_document.imageValue;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self2.imageView.image = image;
                            self2.imageView.hidden = NO;
                            self2.webView.hidden = YES;
                            self2.textView.hidden = YES;
                        });
                    }
                    [self2->_document closeWithCompletionHandler:nil];
                }];
            }
        };

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), onLoaded);

        // Fetch type/last-opened resource values for info labels
        NSURL *infoURL = _info.path;
        NSString *typeIdentifier = nil;
        [infoURL getResourceValue:&typeIdentifier
                           forKey:NSURLTypeIdentifierKey
                            error:nil];
        NSDate *lastOpened = nil;
        [infoURL getResourceValue:&lastOpened
                           forKey:NSURLContentAccessDateKey
                            error:nil];

        self.nameLabel.text = _info.displayName;
        self.kindSizeLabel.text =
            [NSString stringWithFormat:@"%@ - %@", typeIdentifier, _info.sizeLabel];
        self.kindLabel.text = typeIdentifier;
        self.sizeLabel.text = _info.sizeLabel;

        NSDictionary *attrs = _info.attributes;
        self.createdLabel.text =
            [DPHelper displayStringForDate:attrs[NSFileCreationDate]];
        self.modifiedLabel.text =
            [DPHelper displayStringForDate:attrs[NSFileModificationDate]];
        self.lastOpenLabel.text = [DPHelper displayStringForDate:lastOpened];
        self.whereLabel.text = infoURL.path;

        for (UILabel *titleLabel in _infoLabelTitles) {
            titleLabel.text = [[NSBundle mainBundle] localizedStringForKey:titleLabel.text
                                                                     value:@""
                                                                     table:nil];
        }
        _isDocumentLoaded = YES;
    }
}

- (void)setMiniTitleLabelHidden:(BOOL)hidden {
    CGFloat topInset = 0.0;
    if (!hidden) {
        topInset = CGRectGetHeight(self.miniTitleBarBackgroundView.bounds);
    }

    self.miniTitleBarBackgroundView.hidden = hidden;
    self.webView.scrollView.contentInset = UIEdgeInsetsMake(topInset, 0, 0, 0);
    self.textView.contentInset = UIEdgeInsetsMake(topInset, 0, 0, 0);

    if (self.imageView.image) {
        self.imageView.image =
            [self.imageView.image imageWithAlignmentRectInsets:UIEdgeInsetsMake(topInset, 0, 0, 0)];
    }

    if (@available(iOS 11.1, *)) {
        UIEdgeInsets webIns = self.webView.scrollView.verticalScrollIndicatorInsets;
        webIns.top += topInset;
        self.webView.scrollView.verticalScrollIndicatorInsets = webIns;

        UIEdgeInsets textIns = self.textView.verticalScrollIndicatorInsets;
        textIns.top += topInset;
        self.textView.verticalScrollIndicatorInsets = textIns;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIEdgeInsets textIns = self.textView.scrollIndicatorInsets;
        textIns.top += topInset;
        self.textView.scrollIndicatorInsets = textIns;

        UIEdgeInsets webIns = self.webView.scrollView.scrollIndicatorInsets;
        webIns.top += topInset;
        self.webView.scrollView.scrollIndicatorInsets = webIns;
#pragma clang diagnostic pop
    }
}

- (void)dismiss {
    if (self.splitViewController) {
        SEL sel = NSSelectorFromString(@"dismissSecondaryViewController");
        if ([self.splitViewController respondsToSelector:sel]) {
            IMP imp = [self.splitViewController methodForSelector:sel];
            void (*func)(id, SEL) = (void *)imp;
            func(self.splitViewController, sel);
        }
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)openQuickLook {
    QLPreviewController *ql = [[QLPreviewController alloc] init];
    ql.dataSource = self;
    ql.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:ql animated:YES completion:nil];
}

#pragma mark - QLPreviewControllerDelegate / DataSource

- (BOOL)previewController:(QLPreviewController *)controller
            shouldOpenURL:(NSURL *)url
           forPreviewItem:(id<QLPreviewItem>)item {
    return YES;
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return 1;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller
                    previewItemAtIndex:(NSInteger)index {
    return (id<QLPreviewItem>)[(id)_info symbolicPath];
}

- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {
    [super dismissViewControllerAnimated:animated completion:completion];
}

#pragma mark - Fullscreen

- (void)toggleFullscreen {
    [self setFullscreen:!_isFullscreen animated:YES];
}

- (void)setFullscreen:(BOOL)fullscreen animated:(BOOL)animated {
    _isFullscreen = fullscreen;

    void (^animations)(void) = ^{
        self.containerStack.spacing = fullscreen ? 0.0 : 16.0;
        self.labelStackContainer.hidden = fullscreen;

        CGFloat constant = 0.0;
        if (fullscreen) {
            constant = -self.view.safeAreaInsets.bottom;
        }
        self.containerBottomAnchor.constant = constant;

        UIBarButtonItem *toggleItem = fullscreen ? self->_minimizeItem : self->_fullScreenItem;
        self.navigationItem.rightBarButtonItems = @[self->_quickLookItem, toggleItem];

        [self.containerStack layoutIfNeeded];
    };

    if (animated) {
        [UIView animateWithDuration:0.15 animations:animations completion:nil];
    } else {
        animations();
    }
}

#pragma mark - WebKit styling

- (NSString *)interfaceStyleScript {
    NSString *labelHex = [[UIColor dp_labelColor] dp_hexStringValue];
    NSString *bgHex = [[UIColor dp_backgroundColor] dp_hexStringValue];
    NSString *css = [NSString stringWithFormat:@"body { color: %@; background-color: %@; }",
                     labelHex, bgHex];
    return [NSString stringWithFormat:
            @"var style = document.createElement('style'); style.innerHTML = %@; document.head.appendChild(style); document.body.appendChild(style);",
            css];
}

- (void)insertCSSStringInto:(WKWebView *)webView {
    [webView evaluateJavaScript:[self interfaceStyleScript] completionHandler:nil];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self insertCSSStringInto:webView];
}

- (void)updateAppearance {
    [self insertCSSStringInto:self.webView];
}

#pragma mark - Image view tap / fit

- (void)imageViewTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) {
        return;
    }
    BOOL wasDark = _isDarkStyleImageView;
    _isDarkStyleImageView = !wasDark;

    UIColor *bgColor = self.view.backgroundColor;
    UIColor *resolved;
    if (wasDark) {
        UIColor *white = [UIColor whiteColor];
        if (@available(iOS 13.0, *)) {
            UITraitCollection *trait = [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight];
            resolved = [bgColor resolvedColorWithTraitCollection:trait];
        } else {
            resolved = white;
        }
    } else {
        UIColor *black = [UIColor blackColor];
        if (@available(iOS 13.0, *)) {
            UITraitCollection *trait = [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark];
            resolved = [bgColor resolvedColorWithTraitCollection:trait];
        } else {
            resolved = black;
        }
    }
    self.imageView.backgroundColor = resolved;
}

- (CGRect)contentClippingRectForImage:(UIImage *)image {
    CGRect bounds = self.view.bounds;
    if (image && image.size.width > 0.0 && image.size.height > 0.0) {
        CGFloat vw = CGRectGetWidth(bounds);
        CGFloat vh = CGRectGetHeight(bounds);
        CGFloat iw = image.size.width;
        CGFloat ih = image.size.height;
        CGFloat scaleW = vw / iw;
        CGFloat scaleH = vh / ih;
        CGFloat scale = (iw > ih) ? scaleW : scaleH;
        CGFloat outW = scale * iw;
        CGFloat outH = scale * ih;
        CGFloat outX = (vw - outW) * 0.5;
        CGFloat outY = (vh - outH) * 0.5;
        return CGRectMake(outX, outY, outW, outH);
    }
    return bounds;
}

#pragma mark - Context actions / preview actions

- (id)contextActionDataSourceForInfo:(DPPathInfo *)info {
    __weak DPPreviewViewController *weakSelf = self;
    DPPathInfo *target = info;
    return [DPContextActionDataSource dataSourceWithBuilder:^(DPContextActionDataSource *ds) {
        // Open in Filza (group 1)
        [ds action].title(NSLocalizedString(@"Open in Filza", @""))
                   .image([UIImage dp_systemImageNamed:@"folder"])
                   .handler(^{
                       [target openInFilza];
                   })
                   .groupIdentifier(@"1");

        // Open Preview (group 1)
        [ds action].title(NSLocalizedString(@"Open Preview", @""))
                   .image([UIImage dp_systemImageNamed:@"eye"])
                   .handler(^{
                       __strong DPPreviewViewController *s = weakSelf;
                       UIViewController *ctx = [s contextController];
                       UIViewController *preview = [target embeddedPreviewController];
                       [ctx presentViewController:preview animated:YES completion:nil];
                   })
                   .groupIdentifier(@"1");

        // Open Info (group 1)
        [ds action].title(NSLocalizedString(@"Open Info", @""))
                   .image([UIImage dp_systemImageNamed:@"info.circle"])
                   .handler(^{
                       __strong DPPreviewViewController *s = weakSelf;
                       UIViewController *ctx = [s contextController];
                       UINavigationController *nav = ctx.navigationController;
                       UIViewController *infoVC = [target embeddedInfoViewController];
                       [nav presentViewController:infoVC animated:YES completion:nil];
                   })
                   .groupIdentifier(@"1");

        // Copy Path (group 2)
        [ds action].title(NSLocalizedString(@"Copy Path", @""))
                   .image([UIImage dp_systemImageNamed:@"doc.on.doc.fill"])
                   .handler(^{
                       [UIPasteboard generalPasteboard].URL = target.path;
                   })
                   .groupIdentifier(@"2");

        // Copy Name (group 2)
        [ds action].title(NSLocalizedString(@"Copy Name", @""))
                   .image([UIImage dp_systemImageNamed:@"doc.on.doc.fill"])
                   .handler(^{
                       [UIPasteboard generalPasteboard].string = target.name;
                   })
                   .groupIdentifier(@"2");

        // Delete Item (destructive, group 3)
        [ds action].title(NSLocalizedString(@"Delete Item", @""))
                   .image([UIImage dp_systemImageNamed:@"trash.fill"])
                   .handler(^{
                       [target removeOrUninstallItem];
                   })
                   .destructive(YES)
                   .groupIdentifier(@"3");
    }];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (NSArray<UIPreviewAction *> *)previewActionItems {
    id ds = [self contextActionDataSourceForInfo:self.info];
    return (NSArray<UIPreviewAction *> *)[ds previewActionItems];
}
#pragma clang diagnostic pop

@end
