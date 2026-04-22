#import <UIKit/UIKit.h>
#import "DPPathInfo.h"

@interface DPPathCollectionViewCell : UICollectionViewCell

@property (nonatomic, weak) IBOutlet UIImageView *iconView;
@property (nonatomic, weak) IBOutlet UIImageView *shortcutIndicator;
@property (nonatomic, weak) IBOutlet UILabel *titleLabel;
@property (nonatomic, weak) IBOutlet UILabel *label1;
@property (nonatomic, weak) IBOutlet UILabel *label2;
@property (nonatomic, weak) IBOutlet UILabel *label3;
@property (nonatomic, strong) DPPathInfo *info;

- (void)refreshWithInfo:(DPPathInfo *)info interactionController:(UIDocumentInteractionController *)controller;

@end
