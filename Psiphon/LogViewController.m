/*
 * Copyright (c) 2016, Psiphon Inc.
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

#import <Foundation/Foundation.h>
#import "LogViewController.h"
#import "PsiphonData.h"

@implementation LogViewController {
    NSArray *logs;
    UITableView *table;
    NSLock *timerLock;
    NSTimer *reloadTimer;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    timerLock = [[NSLock alloc] init];

    logs = [[PsiphonData sharedInstance] getStatusLogsForDisplay];

    table = [[UITableView alloc] init];
    table.dataSource = self;
    table.delegate = self;
//    table.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
//    table.frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
    table.estimatedRowHeight = 60;
    table.rowHeight = UITableViewAutomaticDimension;

    [self.view addSubview:table];

    // setup autolayout
    table.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:table
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.f
                                                           constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:table
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.f
                                                           constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:table
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeTop
                                                         multiplier:1.f
                                                           constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:table
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.f
                                                           constant:0]];

    [self scheduleReload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(newLogAdded:)
                                                 name:@kDisplayLogEntry
                                               object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super viewWillDisappear:animated];
}

#pragma mark - UITableView delegate methods

// Scroll to bottom of UITableView
-(void)scrollToBottom {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([logs count] > 0) {
            NSIndexPath *myIndexPath = [NSIndexPath indexPathForRow:[logs count]-1 inSection:0];
            [table selectRowAtIndexPath:myIndexPath animated:NO scrollPosition:UITableViewScrollPositionBottom];
        }
    });
}

// Reload data and scroll to bottom of UITableView
-(void)newLogAdded:(id)sender {
    logs = [[PsiphonData sharedInstance] getDiagnosticLogsForDisplay];
    [self scheduleReload];
}

// Performance optimization (prevent UIThread from grinding to a halt from rapid calls to [tableView reloadData])
// TODO: this should be vetted further, there is probably a better solution out there
- (void)scheduleReload {
    BOOL acquired = [timerLock tryLock];
    if (acquired && reloadTimer == nil) {
        __weak LogViewController *weakSelf = self;
        reloadTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                        repeats:NO
                                          block:^(NSTimer *timer){
                                              dispatch_async(dispatch_get_main_queue(), ^{
                                                  [table reloadData];
                                                  [weakSelf scrollToBottom];
                                              });
                                              [reloadTimer invalidate];
                                              reloadTimer = nil;
                                              [timerLock unlock];
                                          }];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [logs count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *statusEntryForDisplay = logs[indexPath.row];

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:statusEntryForDisplay];

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:statusEntryForDisplay];
    }

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.font = [UIFont fontWithName:@"Helvetica" size:12.0f];
    cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.text = statusEntryForDisplay;

    return cell;
}

@end
