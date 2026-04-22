#import <UIKit/UIKit.h>
#import "DPPathInfo.h"

@interface DPPathTableViewCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UIImageView *iconView;
@property (nonatomic, weak) IBOutlet UIImageView *shortcutIndicator;
@property (nonatomic, weak) IBOutlet UILabel *titleLabel;
@property (nonatomic, weak) IBOutlet UILabel *label1;  // modification date
@property (nonatomic, weak) IBOutlet UILabel *label2;  // (reserved)
@property (nonatomic, weak) IBOutlet UILabel *label3;  // size
@property (nonatomic, strong) DPPathInfo *info;

- (void)refreshWithInfo:(DPPathInfo *)info interactionController:(UIDocumentInteractionController *)controller;

@end
