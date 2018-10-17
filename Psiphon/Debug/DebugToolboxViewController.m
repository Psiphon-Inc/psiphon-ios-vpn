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
#import "DispatchUtils.h"


NSString * const ActionCellIdentifier = @"ActionCell";

@implementation DebugToolboxViewController {
    UITableView *actionsTableView;
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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ActionCellIdentifier
            forIndexPath:indexPath];
    switch (indexPath.row) {
        case 0: {
            cell.textLabel.text = @"Full goroutine stack dump";
            UITapGestureRecognizer *gr = [[UITapGestureRecognizer alloc]
                    initWithTarget:self action:@selector(onFullGoRoutineStackDump)];
            [cell addGestureRecognizer:gr];
            break;
        }
        case 1: {
            cell.textLabel.text = @"Stack traces of all goroutines";
            UITapGestureRecognizer *gr = [[UITapGestureRecognizer alloc]
                    initWithTarget:self action:@selector(onGoRoutineStackTrace)];
            [cell addGestureRecognizer:gr];
            break;
        }
        default:
            PSIAssert(FALSE);
    }
    return cell;
}

#pragma mark - PProf

+ (NSURLComponents *)pprofURL {
    NSURLComponents *c = [[NSURLComponents alloc] init];
    c.scheme = @"http";
    c.host = [UIDevice.currentDevice.name.lowercaseString stringByAppendingString:@".local"];
    c.port = @(6060);
    return c;
}

#pragma mark - Action cell tap delegates

- (void)onFullGoRoutineStackDump {
    NSURLComponents *components = [[self class] pprofURL];
    components.path = @"/debug/pprof/goroutine";
    components.query = @"debug=2";
//    [self fetchURL:[components URL] andPresentWithTitle:@"/pprof/goroutine?debug=2"];

    [self presentWithSafari:[components URL]];
}

- (void)onGoRoutineStackTrace {
    NSURLComponents *components = [[self class] pprofURL];
    components.path = @"/debug/pprof/goroutine";
    components.query = @"debug=1";
//    [self fetchURL:[components URL] andPresentWithTitle:@"/pprof/goroutine?debug=1"];
    [self presentWithSafari:[components URL]];
}

#pragma mark - DebugTextViewController presentation

- (void)presentWithSafari:(NSURL *)url {
    SFSafariViewController *safari = [[SFSafariViewController alloc]initWithURL:url entersReaderIfAvailable:NO];
    [self presentViewController:safari animated:TRUE completion:nil];
}

@end
