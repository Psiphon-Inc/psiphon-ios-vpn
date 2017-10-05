/*
 * Copyright (c) 2017, Psiphon Inc.
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

#import "LogViewControllerFullScreen.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "Notifier.h"

// Number logs to display
#define NUM_LOGS_DISPLAY 250

@implementation LogViewControllerFullScreen {
    PsiphonDataSharedDB *sharedDB;
    Notifier *notifier;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // UIBar
    [self setTitle:NSLocalizedStringWithDefaultValue(@"LOGS_TITLE", nil, [NSBundle mainBundle], @"Logs", @"Log view title bar text")];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc]
      initWithTitle:NSLocalizedStringWithDefaultValue(@"DONE_ACTION", nil, [NSBundle mainBundle], @"Done", @"Done button in navigation bar")
      style:UIBarButtonItemStyleDone target:self action:@selector(onNavigationDoneTap)];

    [self.navigationItem setRightBarButtonItem:doneButton];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<DiagnosticEntry*> *entries = [sharedDB getAllLogs];
        self.diagnosticEntries = [entries subarrayWithRange:NSMakeRange([entries count] - NUM_LOGS_DISPLAY , NUM_LOGS_DISPLAY)];
        [self onDataChanged];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    // TODO: is this the best place to stop listening for notifications?
    [notifier stopListeningForAllNotifications];
}

- (void)onNavigationDoneTap {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
