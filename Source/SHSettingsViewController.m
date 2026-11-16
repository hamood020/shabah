#import "SHSettingsViewController.h"
#import "SHPersistence.h"
#import "SHTheme.h"
#import "SHUpdateChecker.h"

typedef NS_ENUM(NSInteger, SHSettingsSection) {
    SHSectionGeneral,
    SHSectionHelp,
    SHSectionAbout,
    SHSectionCount,
};

static NSString *SHMapStyleTitle(NSInteger style) {
    switch (style) {
        case 1: return SHText(@"style_satellite");
        case 2: return SHText(@"style_hybrid");
        case 3: return SHText(@"style_night");
        default: return SHText(@"style_standard");
    }
}

@implementation SHSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self applyLanguage];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)applyLanguage {
    self.title = SHText(@"settings");
    self.navigationController.navigationBar.semanticContentAttribute = [SHTheme direction];
    self.tableView.semanticContentAttribute = [SHTheme direction];
    [self.tableView reloadData];
}

- (void)notifyChange {
    if (self.onChange) self.onChange();
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return SHSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SHSectionGeneral: return 3;
        case SHSectionHelp:    return 3;
        case SHSectionAbout:   return 4;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SHSectionGeneral: return SHText(@"general");
        case SHSectionHelp:    return SHText(@"help");
        case SHSectionAbout:   return SHText(@"about");
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    SHPersistence *store = [SHPersistence shared];

    if (indexPath.section == SHSectionGeneral) {
        if (indexPath.row == 0) {
            cell.textLabel.text = SHText(@"language");
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"العربية", @"English"]];
            seg.selectedSegmentIndex = store.arabic ? 0 : 1;
            [seg addTarget:self action:@selector(languageChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = SHText(@"map_style");
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            [button setTitle:SHMapStyleTitle(store.mapStyle) forState:UIControlStateNormal];
            NSMutableArray *actions = [NSMutableArray array];
            __weak typeof(self) weakSelf = self;
            for (NSInteger style = 0; style < 4; style++) {
                UIAction *a = [UIAction actionWithTitle:SHMapStyleTitle(style) image:nil identifier:nil handler:^(UIAction *action) {
                    [SHPersistence shared].mapStyle = style;
                    [weakSelf.tableView reloadData];
                    [weakSelf notifyChange];
                }];
                a.state = store.mapStyle == style ? UIMenuElementStateOn : UIMenuElementStateOff;
                [actions addObject:a];
            }
            button.menu = [UIMenu menuWithChildren:actions];
            button.showsMenuAsPrimaryAction = YES;
            [button sizeToFit];
            cell.accessoryView = button;
        } else {
            cell.textLabel.text = SHText(@"check_updates");
            UISwitch *sw = [SHTheme switchView];
            sw.on = store.checkUpdates;
            [sw addTarget:self action:@selector(updatesToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    } else if (indexPath.section == SHSectionHelp) {
        NSArray *keys = @[@"help_tap", @"help_hold", @"help_three"];
        NSArray *icons = @[@"hand.tap", @"hand.point.up.left", @"hand.raised"];
        cell.textLabel.text = SHText(keys[indexPath.row]);
        cell.textLabel.numberOfLines = 0;
        cell.imageView.image = [UIImage systemImageNamed:icons[indexPath.row]];
        cell.imageView.tintColor = [SHTheme accent];
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = SHText(@"version");
                cell.detailTextLabel.text = SH_VERSION;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                break;
            case 1:
                cell.textLabel.text = SHText(@"check_now");
                cell.textLabel.textColor = [SHTheme accent];
                break;
            case 2:
                cell.textLabel.text = SHText(@"copy_log");
                cell.textLabel.textColor = [SHTheme accent];
                break;
            case 3:
                cell.textLabel.text = SHText(@"project_page");
                cell.textLabel.textColor = [SHTheme accent];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
        }
    }
    [SHTheme applyDirectionToView:cell];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != SHSectionAbout) return;
    switch (indexPath.row) {
        case 1: {
            [SHUpdateChecker checkForce:YES completion:^(NSString *newer, NSURL *page, BOOL failed) {
                if (newer) {
                    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil
                        message:[NSString stringWithFormat:SHText(@"update_fmt"), newer] preferredStyle:UIAlertControllerStyleAlert];
                    [ac addAction:[UIAlertAction actionWithTitle:SHText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
                    [ac addAction:[UIAlertAction actionWithTitle:SHText(@"open") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                        if (page) [UIApplication.sharedApplication openURL:page options:@{} completionHandler:nil];
                    }]];
                    [self presentViewController:ac animated:YES completion:nil];
                } else {
                    [self showMessage:failed ? SHText(@"update_fail") : SHText(@"up_to_date")];
                }
            }];
            break;
        }
        case 2:
            UIPasteboard.generalPasteboard.string = SHLogDump();
            [self showMessage:SHText(@"log_copied")];
            break;
        case 3: {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/%@", SH_REPO]];
            [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
            break;
        }
    }
}

#pragma mark - Actions

- (void)languageChanged:(UISegmentedControl *)seg {
    [SHPersistence shared].arabic = seg.selectedSegmentIndex == 0;
    [self applyLanguage];
    [self notifyChange];
}

- (void)updatesToggled:(UISwitch *)sw {
    [SHPersistence shared].checkUpdates = sw.on;
}

- (void)showMessage:(NSString *)message {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:SHText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
