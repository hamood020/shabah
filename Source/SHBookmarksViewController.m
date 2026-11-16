#import "SHBookmarksViewController.h"
#import "SHPersistence.h"

@implementation SHBookmarksViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SHText(@"bookmarks");
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.view.semanticContentAttribute = [SHPersistence shared].arabic
        ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(1, (NSInteger)[SHPersistence shared].bookmarks.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    NSArray *list = [SHPersistence shared].bookmarks;
    if (list.count == 0) {
        cell.textLabel.text = SHText(@"no_bookmarks");
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *item = list[indexPath.row];
    cell.textLabel.text = item[@"name"];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.6f, %.6f", [item[@"lat"] doubleValue], [item[@"lon"] doubleValue]];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [SHPersistence shared].bookmarks.count > 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete) return;
    [[SHPersistence shared] removeBookmarkAtIndex:indexPath.row];
    [tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *list = [SHPersistence shared].bookmarks;
    if (indexPath.row >= (NSInteger)list.count) return;
    NSDictionary *item = list[indexPath.row];
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake([item[@"lat"] doubleValue], [item[@"lon"] doubleValue]);
    if (self.onSelect) self.onSelect(c, item[@"name"]);
}

@end
