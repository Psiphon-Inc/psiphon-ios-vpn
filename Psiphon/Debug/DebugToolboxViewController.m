/*
 * Copyright (c) 2018, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import <SafariServices/SafariServices.h>
#import "DebugToolboxViewController.h"
#import "Asserts.h"
#import "Notifier.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "DebugDirectoryViewerViewController.h"

#if DEBUG

NSString * const ActionCellIdentifier = @"ActionCell";
NSString * const SwitchCellIdentifier = @"SwitchCell";

@interface DebugToolboxViewController ()

@property (nonatomic) PsiphonDataSharedDB *sharedDB;

@end

@implementation DebugToolboxViewController {
    UITableView *actionsTableView;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Navigation bar
    self.title = @"Toolbox";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                 target:self
                                 action:@selector(dismiss)];

    actionsTableView = [[UITableView alloc] init];
    actionsTableView.dataSource = self;
    actionsTableView.delegate = self;
    [actionsTableView registerClass:UITableViewCell.class forCellReuseIdentifier:ActionCellIdentifier];
    [actionsTableView registerClass:UITableViewCell.class forCellReuseIdentifier:SwitchCellIdentifier];
    actionsTableView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:actionsTableView];

    // Layout constraints
    actionsTableView.translatesAutoresizingMaskIntoConstraints = FALSE;
    [actionsTableView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = TRUE;
    [actionsTableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = TRUE;
    [actionsTableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = TRUE;
    [actionsTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = TRUE;
}

- (void)dismiss {
    [self dismissViewControllerAnimated:TRUE completion:nil];
}

#pragma mark - UITableViewDataSource delegate methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2; // PPROF
        case 1: return 2; // EXTENSION
        default:
            PSIAssert(FALSE)
            return 0;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"PPROF";
        case 1: return @"EXTENSION";
        default:
            PSIAssert(FALSE);
            return @"";
    }
}



- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell;
    SEL action = nil;

    // PPROF section
    if (indexPath.section == 0) {

        cell = [tableView dequeueReusableCellWithIdentifier:ActionCellIdentifier forIndexPath:indexPath];
        switch (indexPath.row) {
            case 0: {
                cell.textLabel.text = @"Write Go Profiles";
                action = @selector(onWriteGoProfiles);
                break;
            }
            case 1: {
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.textLabel.text = @"Show Go Profiles";
                action = @selector(onGoProfiles);
                break;
            }
        }

    // EXTENSION section
    } else if (indexPath.section == 1) {

        switch (indexPath.row) {
            case 0: {
                cell = [tableView dequeueReusableCellWithIdentifier:ActionCellIdentifier forIndexPath:indexPath];
                cell.textLabel.text = @"Force Jetsam";
                action = @selector(onForceJetsam);
                break;
            }
            case 1: {
                cell = [tableView dequeueReusableCellWithIdentifier:ActionCellIdentifier forIndexPath:indexPath];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.textLabel.text = @"Memory Profiler";
                UISwitch *switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
                [switchView setOn:self.sharedDB.getDebugMemoryProfiler];
                [switchView addTarget:self
                               action:@selector(onMemoryProfilerSwitch:)
                     forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = switchView;
                break;
            }
        }
    }

    if (action != nil) {
        UITapGestureRecognizer *gr = [[UITapGestureRecognizer alloc]
                initWithTarget:self action:action];
        [cell addGestureRecognizer:gr];
    }

    return cell;
}

#pragma mark - Action cell tap delegates

- (void)onForceJetsam {
    [[Notifier sharedInstance] post:NotifierDebugForceJetsam];
}

- (void)onWriteGoProfiles {
    [[Notifier sharedInstance] post:NotifierDebugGoProfile];
}

- (void)onGoProfiles {
    NSURL *dirURL = [NSURL fileURLWithPath:self.sharedDB.goProfileDirectory];

    DebugDirectoryViewerViewController *wvc = [DebugDirectoryViewerViewController createAndLoadDirectory:dirURL
            withTitle:@"Go Profiles"];
    [self.navigationController pushViewController:wvc animated:TRUE];
}

- (void)onMemoryProfilerSwitch:(UISwitch *)view {
    [self.sharedDB setDebugMemoryProfiler:view.isOn];
    [[Notifier sharedInstance] post:NotifierDebugMemoryProfiler];
}

@end

#endif
