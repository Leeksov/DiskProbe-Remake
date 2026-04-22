#import "DPPathTableViewCell.h"
#import "DPHelper.h"
#import "UIColor+DP.h"
#import "DPVersionCheck.h"
#import <objc/message.h>

@implementation DPPathTableViewCell

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
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
}

- (void)refreshWithInfo:(DPPathInfo *)info interactionController:(UIDocumentInteractionController *)controller {
    self.info = info;

    // Title
    self.titleLabel.text = info.displayName;

    // Labels (label1 = modification date, label2 reserved, label3 = size)
    NSString *dateLabel = info.modificationDateLabel;
    if (!dateLabel.length && info.modificationDate) {
        dateLabel = [DPHelper displayStringForDate:info.modificationDate style:1];
    }
    self.label1.text = dateLabel;
    self.label2.text = nil;
    self.label3.text = info.sizeLabel;
    NSLog(@"[DiskProbe] refreshWithInfo name=%@ mod=%@ size=%@", info.displayName, dateLabel, info.sizeLabel);

    // Symlink indicator
    self.shortcutIndicator.hidden = !info.isSymbolicLink;

    // Icon — the underlying method actually takes the interaction controller
    // (it calls -icons on it). Dispatch via performSelector: to pass the object
    // through while keeping the public enum-based header signature compatible.
    UIImage *icon = ((UIImage *(*)(id, SEL, id))objc_msgSend)(info, @selector(displayImageWithSource:), controller);
    self.iconView.image = icon;

    // Accessory — IDA passes raw isDirectory BOOL (0/1); 1 == DisclosureIndicator
    self.accessoryType = (UITableViewCellAccessoryType)info.isDirectory;

    // Title color — iOS 13+ uses dynamic colors; earlier uses static darkText/systemPurple
    UIColor *titleColor;
    if (DPIsIOS13OrLater()) {
        if (info.isSymbolicLink)      titleColor = [UIColor systemIndigoColor];
        else if (info.isApplication)  titleColor = [UIColor systemBlueColor];
        else                          titleColor = [UIColor labelColor];
    } else {
        if (info.isSymbolicLink)      titleColor = [UIColor systemPurpleColor];
        else if (info.isApplication)  titleColor = [UIColor systemBlueColor];
        else                          titleColor = [UIColor darkTextColor];
    }
    CGFloat alpha = info.isHidden ? 0.6 : 1.0;
    self.titleLabel.textColor = [titleColor colorWithAlphaComponent:alpha];

    // Fonts (dynamic type) — reapplied every refresh to match IDA
    UIFont *captionFont = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.label1.font = captionFont;
    self.label2.font = captionFont;
    self.label3.font = captionFont;
}

@end
