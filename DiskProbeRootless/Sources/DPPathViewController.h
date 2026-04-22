#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>
#import "DPDirectoryDataSource.h"
#import "DPInfoHeader.h"
#import "DPNavigationPathView.h"

@interface DPPathViewController : UIViewController
    <UITableViewDelegate, UITableViewDataSource,
     UICollectionViewDelegate, UICollectionViewDataSource,
     UICollectionViewDelegateFlowLayout,
     UISearchResultsUpdating, UISearchBarDelegate,
     UIDocumentInteractionControllerDelegate,
     UIPopoverPresentationControllerDelegate,
     DPDirectoryDataSourceDelegate,
     DPInfoHeaderDelegate,
     DPNavigationPathViewDelegate,
     QLPreviewControllerDataSource, QLPreviewControllerDelegate>

@property (nonatomic, weak) IBOutlet UITableView *tableView;
@property (nonatomic, weak) IBOutlet UICollectionView *collectionView;
@property (nonatomic, strong) DPDirectoryDataSource *dataSource;

+ (instancetype)directoryViewControllerWithDirectory:(NSString *)directory;
- (void)goToDirectory:(NSString *)directory animated:(BOOL)animated;

@end
