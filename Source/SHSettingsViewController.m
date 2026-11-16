#import "SHSettingsViewController.h"
#import "SHPersistence.h"
#import "SHTheme.h"
#import "SHUpdateChecker.h"
#import "SHScheduler.h"
#import "SHScheduleViewController.h"

typedef NS_ENUM(NSInteger, SHSettingsSection) {
    SHSectionGeneral,
    SHSectionAppearance,
    SHSectionTools,
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
    [self.tableView reloadData];
}

- (void)applyLanguage {
    self.title = SHText(@"settings");
    self.navigationController.navigationBar.semanticContentAttribute = [SHTheme direction];
    self.navigationController.navigationBar.tintColor = [SHTheme accent];
    self.tableView.semanticContentAttribute = [SHTheme direction];
    [self.tableView reloadData];
}

- (void)notifyChange {
    if (self.onChange) self.onChange();
}

#pragma mark - Builders

- (UIButton *)menuButtonWithTitle:(NSString *)title actions:(NSArray<UIAction *> *)actions {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.tintColor = [SHTheme accent];
    button.menu = [UIMenu menuWithChildren:actions];
    button.showsMenuAsPrimaryAction = YES;
    [button sizeToFit];
    return button;
}

- (UISwitch *)switchOn:(BOOL)on action:(SEL)action {
    UISwitch *sw = [SHTheme switchView];
    sw.on = on;
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (UISlider *)sliderFrom:(float)min to:(float)max value:(float)value action:(SEL)action {
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 32)];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    slider.minimumTrackTintColor = [SHTheme accent];
    [slider addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return slider;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return SHSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SHSectionGeneral:    return 3;
        case SHSectionAppearance: return 4;
        case SHSectionTools:      return 4;
        case SHSectionHelp:       return 4;
        case SHSectionAbout:      return 4;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SHSectionGeneral:    return SHText(@"general");
        case SHSectionAppearance: return SHText(@"appearance");
        case SHSectionTools:      return SHText(@"tools");
        case SHSectionHelp:       return SHText(@"help");
        case SHSectionAbout:      return SHText(@"about");
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.numberOfLines = 2;
    SHPersistence *store = [SHPersistence shared];
    __weak typeof(self) weakSelf = self;

    switch (indexPath.section) {
        case SHSectionGeneral:
            if (indexPath.row == 0) {
                cell.textLabel.text = SHText(@"language");
                UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"العربية", @"English"]];
                seg.selectedSegmentIndex = store.arabic ? 0 : 1;
                [seg addTarget:self action:@selector(languageChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = seg;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = SHText(@"map_style");
                NSMutableArray *actions = [NSMutableArray array];
                for (NSInteger style = 0; style < 4; style++) {
                    UIAction *a = [UIAction actionWithTitle:SHMapStyleTitle(style) image:nil identifier:nil handler:^(UIAction *action) {
                        [SHPersistence shared].mapStyle = style;
                        [weakSelf.tableView reloadData];
                        [weakSelf notifyChange];
                    }];
                    a.state = store.mapStyle == style ? UIMenuElementStateOn : UIMenuElementStateOff;
                    [actions addObject:a];
                }
                cell.accessoryView = [self menuButtonWithTitle:SHMapStyleTitle(store.mapStyle) actions:actions];
            } else {
                cell.textLabel.text = SHText(@"check_updates");
                cell.accessoryView = [self switchOn:store.checkUpdates action:@selector(updatesToggled:)];
            }
            break;

        case SHSectionAppearance:
            if (indexPath.row == 0) {
                cell.textLabel.text = SHText(@"theme");
                NSMutableArray *actions = [NSMutableArray array];
                for (NSInteger i = 0; i < [SHTheme themeCount]; i++) {
                    UIImage *dot = [[UIImage systemImageNamed:@"circle.fill"] imageWithTintColor:[SHTheme accentForTheme:i]
                                                                                    renderingMode:UIImageRenderingModeAlwaysOriginal];
                    UIAction *a = [UIAction actionWithTitle:[SHTheme themeNameAtIndex:i] image:dot identifier:nil handler:^(UIAction *action) {
                        [SHPersistence shared].themeIndex = i;
                        [weakSelf applyLanguage];
                        [weakSelf notifyChange];
                    }];
                    a.state = store.themeIndex == i ? UIMenuElementStateOn : UIMenuElementStateOff;
                    [actions addObject:a];
                }
                cell.accessoryView = [self menuButtonWithTitle:[SHTheme themeNameAtIndex:store.themeIndex] actions:actions];
            } else if (indexPath.row == 1) {
                cell.textLabel.text = SHText(@"button_size");
                cell.accessoryView = [self sliderFrom:44 to:76 value:store.buttonSize action:@selector(sizeChanged:)];
            } else if (indexPath.row == 2) {
                cell.textLabel.text = SHText(@"button_opacity");
                cell.accessoryView = [self sliderFrom:0.35 to:1 value:store.buttonOpacity action:@selector(opacityChanged:)];
            } else {
                cell.textLabel.text = SHText(@"status_pill");
                cell.accessoryView = [self switchOn:store.statusPillEnabled action:@selector(pillToggled:)];
            }
            break;

        case SHSectionTools:
            if (indexPath.row == 0) {
                cell.textLabel.text = SHText(@"schedule");
                cell.detailTextLabel.text = store.scheduleEnabled ? SHText(@"on") : SHText(@"off");
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                cell.imageView.image = [UIImage systemImageNamed:@"calendar.badge.clock"];
                cell.imageView.tintColor = [SHTheme accent];
            } else if (indexPath.row == 1) {
                cell.textLabel.text = SHText(@"expiry_notify");
                cell.accessoryView = [self switchOn:store.expiryNotifications action:@selector(notifyToggled:)];
            } else if (indexPath.row == 2) {
                cell.textLabel.text = SHText(@"volume_gesture");
                cell.accessoryView = [self switchOn:store.volumeGestureEnabled action:@selector(volumeToggled:)];
            } else {
                cell.textLabel.text = SHText(@"real_location");
                cell.accessoryView = [self switchOn:store.showRealLocation action:@selector(realLocationToggled:)];
            }
            break;

        case SHSectionHelp: {
            NSArray *keys = @[@"help_tap", @"help_hold", @"help_three", @"help_volume"];
            NSArray *icons = @[@"hand.tap", @"hand.point.up.left", @"hand.raised", @"speaker.wave.2"];
            cell.textLabel.text = SHText(keys[indexPath.row]);
            cell.textLabel.numberOfLines = 0;
            cell.imageView.image = [UIImage systemImageNamed:icons[indexPath.row]];
            cell.imageView.tintColor = [SHTheme accent];
            break;
        }

        case SHSectionAbout:
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
            break;
    }
    [SHTheme applyDirectionToView:cell];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == SHSectionTools && indexPath.row == 0) {
        [self.navigationController pushViewController:[[SHScheduleViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
        return;
    }
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

- (void)updatesToggled:(UISwitch *)sw       { [SHPersistence shared].checkUpdates = sw.on; }
- (void)sizeChanged:(UISlider *)slider      { [SHPersistence shared].buttonSize = round(slider.value); }
- (void)opacityChanged:(UISlider *)slider   { [SHPersistence shared].buttonOpacity = slider.value; }
- (void)pillToggled:(UISwitch *)sw          { [SHPersistence shared].statusPillEnabled = sw.on; }
- (void)volumeToggled:(UISwitch *)sw        { [SHPersistence shared].volumeGestureEnabled = sw.on; }

- (void)realLocationToggled:(UISwitch *)sw {
    [SHPersistence shared].showRealLocation = sw.on;
    [self notifyChange];
}

- (void)notifyToggled:(UISwitch *)sw {
    if (!sw.on) {
        [SHPersistence shared].expiryNotifications = NO;
        return;
    }
    [[SHScheduler shared] requestNotificationPermission:^(BOOL granted) {
        [SHPersistence shared].expiryNotifications = granted;
        sw.on = granted;
        if (!granted) [self showMessage:SHText(@"notify_denied")];
    }];
}

- (void)showMessage:(NSString *)message {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:SHText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
