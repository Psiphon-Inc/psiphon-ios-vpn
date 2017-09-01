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

@implementation LogViewControllerFullScreen {
    PsiphonData *psiphonData;
    PsiphonDataSharedDB *sharedDB;
    Notifier *notifier;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        psiphonData = [PsiphonData sharedInstance];
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
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Reads data from the database on a global background thread,
    // and populates psiphonData in-memory database.
    // LogViewControllers listens for new log notifications from PsiphonData.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<DiagnosticEntry *> *logs = [sharedDB getNewLogs];
        [psiphonData addDiagnosticEntries:logs];
    });

    [notifier listenForNotification:@"NE.onDiagnosticMessage" listener:^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray<DiagnosticEntry *> *logs = [sharedDB getNewLogs];
            [psiphonData addDiagnosticEntries:logs];

#if DEBUG
            for (DiagnosticEntry *log in logs) {
                NSLog(@"%@ %@", [log getTimestampForDisplay], [log message]);
            }
#endif
        });
    }];
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
