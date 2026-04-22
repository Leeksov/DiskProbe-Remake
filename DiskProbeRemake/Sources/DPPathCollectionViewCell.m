#import "DPPathCollectionViewCell.h"
#import "DPHelper.h"
#import "UIColor+DP.h"
#import "DPVersionCheck.h"
#import <objc/message.h>

@implementation DPPathCollectionViewCell

- (void)awakeFromNib {
    [super awakeFromNib];

    UIFont *captionFont = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.titleLabel.font = captionFont;
    self.label1.font = captionFont;
    self.label2.font = captionFont;
    self.label3.font = captionFont;

    self.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.label1.adjustsFontForContentSizeCategory = YES;
    self.label2.adjustsFontForContentSizeCategory = YES;
    self.label3.adjustsFontForContentSizeCategory = YES;

    self.iconView.contentMode = UIViewContentModeScaleAspectFit;

    self.layer.cornerRadius = 13.0;
    self.layer.masksToBounds = YES;
    if (DPIsIOS13OrLater()) {
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
    }
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    self.backgroundColor = selected ? [UIColor dp_separatorColor] : [UIColor clearColor];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? [UIColor dp_separatorColor] : [UIColor clearColor];
}

- (void)refreshWithInfo:(DPPathInfo *)info interactionController:(UIDocumentInteractionController *)controller {
    self.info = info;

    self.titleLabel.text = info.displayName;

    // label1: modification date formatted with style 1 (short)
    if (info.modificationDate) {
        self.label1.text = [DPHelper displayStringForDate:info.modificationDate style:1];
    } else {
        self.label1.text = nil;
    }
    self.label2.text = nil;
    self.label3.text = info.sizeLabel;

    self.shortcutIndicator.hidden = !info.isSymbolicLink;

    // Icon — the underlying method actually takes the interaction controller
    // (it calls -icons on it). Dispatch via objc_msgSend to pass the object
    // through while keeping the public enum-based header signature compatible.
    UIImage *icon = ((UIImage *(*)(id, SEL, id))objc_msgSend)(info, @selector(displayImageWithSource:), controller);
    self.iconView.image = icon;

    UIColor *titleColor;
    if (DPIsIOS13OrLater()) {
        if (info.isSymbolicLink)     titleColor = [UIColor systemIndigoColor];
        else if (info.isApplication) titleColor = [UIColor systemBlueColor];
        else                         titleColor = [UIColor labelColor];
    } else {
        if (info.isSymbolicLink)     titleColor = [UIColor systemPurpleColor];
        else if (info.isApplication) titleColor = [UIColor systemBlueColor];
        else                         titleColor = [UIColor darkTextColor];
    }
    CGFloat alpha = info.isHidden ? 0.6 : 1.0;
    self.titleLabel.textColor = [titleColor colorWithAlphaComponent:alpha];

    UIFont *captionFont = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.label1.font = captionFont;
    self.label2.font = captionFont;
    self.label3.font = captionFont;
}

@end
