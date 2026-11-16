#import "SHScheduleViewController.h"
#import "SHPersistence.h"
#import "SHScheduler.h"
#import "SHTheme.h"

typedef NS_ENUM(NSInteger, SHScheduleSection) {
    SHScheduleSectionMain,
    SHScheduleSectionDays,
    SHScheduleSectionTimes,
    SHScheduleSectionPlace,
    SHScheduleSectionCount,
};

static NSDate *SHDateFromMinutes(NSInteger minutes) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
    c.hour = minutes / 60;
    c.minute = minutes % 60;
    return [cal dateFromComponents:c];
}

static NSInteger SHMinutesFromDate(NSDate *date) {
    NSDateComponents *c = [[NSCalendar currentCalendar] components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:date];
    return c.hour * 60 + c.minute;
}

@implementation SHScheduleViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SHText(@"schedule");
    self.tableView.semanticContentAttribute = [SHTheme direction];
    __weak typeof(self) weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:SHPlacesChangedNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *n) { [weakSelf.tableView reloadData]; }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return SHScheduleSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SHScheduleSectionMain:  return 1;
        case SHScheduleSectionDays:  return 7;
        case SHScheduleSectionTimes: return 2;
        case SHScheduleSectionPlace: return 1 + (NSInteger)[SHPersistence shared].bookmarks.count;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SHScheduleSectionDays:  return SHText(@"sched_days");
        case SHScheduleSectionTimes: return SHText(@"sched_times");
        case SHScheduleSectionPlace: return SHText(@"sched_place");
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == SHScheduleSectionMain) {
        NSString *next = [[SHScheduler shared] nextEventDescription];
        return next ? [NSString stringWithFormat:@"%@\n\n%@", SHText(@"sched_footer"), next] : SHText(@"sched_footer");
    }
    if (section == SHScheduleSectionPlace && [SHPersistence shared].bookmarks.count == 0) return SHText(@"sched_need_bookmark");
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    SHPersistence *store = [SHPersistence shared];
    cell.tintColor = [SHTheme accent];

    switch (indexPath.section) {
        case SHScheduleSectionMain: {
            cell.textLabel.text = SHText(@"sched_enable");
            UISwitch *sw = [SHTheme switchView];
            sw.on = store.scheduleEnabled;
            [sw addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case SHScheduleSectionDays: {
            // Show the week starting on Saturday, as is common in the Gulf.
            NSInteger weekday = ((indexPath.row + 6) % 7) + 1;   // 7=Sat, 1=Sun, ... 6=Fri
            NSArray<NSString *> *names = [SHPersistence shared].arabic
                ? @[@"الأحد", @"الإثنين", @"الثلاثاء", @"الأربعاء", @"الخميس", @"الجمعة", @"السبت"]
                : @[@"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday", @"Saturday"];
            cell.textLabel.text = names[weekday - 1];
            cell.accessoryType = [store.scheduleDays containsObject:@(weekday)] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            cell.tag = weekday;
            break;
        }
        case SHScheduleSectionTimes: {
            BOOL isStart = indexPath.row == 0;
            cell.textLabel.text = isStart ? SHText(@"sched_from") : SHText(@"sched_to");
            UIDatePicker *picker = [UIDatePicker new];
            picker.datePickerMode = UIDatePickerModeTime;
            picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
            picker.minuteInterval = 5;
            picker.date = SHDateFromMinutes(isStart ? store.scheduleStartMinutes : store.scheduleEndMinutes);
            picker.tag = isStart ? 0 : 1;
            [picker addTarget:self action:@selector(timeChanged:) forControlEvents:UIControlEventValueChanged];
            [picker sizeToFit];
            cell.accessoryView = picker;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case SHScheduleSectionPlace: {
            NSDictionary *current = store.scheduleLocation;
            if (indexPath.row == 0) {
                cell.textLabel.text = SHText(@"sched_current_spot");
                cell.detailTextLabel.text = store.hasCoordinate
                    ? [NSString stringWithFormat:@"%.5f, %.5f", store.coordinate.latitude, store.coordinate.longitude] : @"—";
                cell.imageView.image = [UIImage systemImageNamed:@"location.fill"];
            } else {
                NSDictionary *place = store.bookmarks[indexPath.row - 1];
                cell.textLabel.text = place[@"name"];
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%.5f, %.5f", [place[@"lat"] doubleValue], [place[@"lon"] doubleValue]];
                cell.imageView.image = [UIImage systemImageNamed:@"star.fill"];
                BOOL selected = current && fabs([current[@"lat"] doubleValue] - [place[@"lat"] doubleValue]) < 1e-7
                                        && fabs([current[@"lon"] doubleValue] - [place[@"lon"] doubleValue]) < 1e-7;
                cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            }
            cell.imageView.tintColor = [SHTheme accent];
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            if (indexPath.row == 0 && current && !cell.accessoryType) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", SHText(@"sched_selected"), current[@"name"] ?: @""];
            }
            break;
        }
    }
    [SHTheme applyDirectionToView:cell];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SHPersistence *store = [SHPersistence shared];

    if (indexPath.section == SHScheduleSectionDays) {
        NSInteger weekday = [tableView cellForRowAtIndexPath:indexPath].tag;
        NSMutableArray *days = [store.scheduleDays mutableCopy];
        if ([days containsObject:@(weekday)]) [days removeObject:@(weekday)];
        else [days addObject:@(weekday)];
        store.scheduleDays = days;
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:SHScheduleSectionDays] withRowAnimation:UITableViewRowAnimationNone];
    } else if (indexPath.section == SHScheduleSectionPlace) {
        if (indexPath.row == 0) {
            if (!store.hasCoordinate) return;
            CLLocationCoordinate2D c = store.coordinate;
            store.scheduleLocation = @{ @"name": SHText(@"sched_current_spot"), @"lat": @(c.latitude), @"lon": @(c.longitude) };
        } else {
            NSDictionary *place = store.bookmarks[indexPath.row - 1];
            store.scheduleLocation = @{ @"name": place[@"name"] ?: @"", @"lat": place[@"lat"], @"lon": place[@"lon"] };
        }
        [tableView reloadData];
    }
}

#pragma mark - Actions

- (void)enabledChanged:(UISwitch *)sw {
    SHPersistence *store = [SHPersistence shared];
    if (sw.on && !store.scheduleLocation) {
        sw.on = NO;
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:SHText(@"sched_pick_place") preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:SHText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }
    store.scheduleEnabled = sw.on;
    [self.tableView reloadData];
}

- (void)timeChanged:(UIDatePicker *)picker {
    NSInteger minutes = SHMinutesFromDate(picker.date);
    if (picker.tag == 0) [SHPersistence shared].scheduleStartMinutes = minutes;
    else [SHPersistence shared].scheduleEndMinutes = minutes;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SHScheduleSectionMain] withRowAnimation:UITableViewRowAnimationNone];
}

@end
