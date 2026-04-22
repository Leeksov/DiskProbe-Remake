#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DPTableViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong, nullable) UITableView *tableView;
@property (nonatomic, strong, nullable) NSDictionary *data;
@property (nonatomic, assign) UITableViewCellStyle cellStyle;
@property (nonatomic, strong, nullable) NSIndexPath *lastSelectedIndexPath;
@property (nonatomic, strong) NSMutableArray *disabledIndexPaths;

+ (instancetype)tableViewControllerWithPlist:(NSString *)plistName;
+ (instancetype)tableViewControllerWithDataSource:(NSDictionary *)dataSource;
+ (instancetype)tableViewControllerWithDataSource:(NSDictionary *)dataSource cellStyle:(UITableViewCellStyle)cellStyle;

- (instancetype)initWithData:(NSDictionary *)data;

- (NSDictionary *)dataForIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *_Nullable)indexPathForPrefsKey:(NSString *)prefsKey;
- (NSDictionary *)dataSource;
- (UITableViewCellStyle)cellStyleForString:(NSString *)string;
- (UITableViewCellAccessoryType)accessoryTypeForString:(NSString *)string;
- (NSString *)stringForDataValue:(id)value;
- (void)setCellForRowAtIndexPath:(NSIndexPath *)indexPath enabled:(BOOL)enabled animated:(BOOL)animated;
- (void)dismiss;
- (void)controlDidChangeValue:(id)sender;
- (void)controlDidChangeValue:(id)sender authentication:(NSUInteger)auth;

@end

NS_ASSUME_NONNULL_END
