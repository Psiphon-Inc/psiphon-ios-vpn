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
#import "Logging.h"

// Initial maximum number of logs to load.
#define MAX_LOGS_LOAD 250

/*
 * Limitations:
 *      - Only the main rotating_notices log file and not the backup
 *        is read and monitored for changes.
 *      - File change monitoring fails if file the log file has not been created yet.
 *      - Log file truncation is not handled.
 */
@implementation LogViewControllerFullScreen {

    UIActivityIndicatorView *activityIndicator;

    PsiphonDataSharedDB *sharedDB;

    NSFileHandle *logFileHandle;
    unsigned long long bytesReadFileOffset;
    dispatch_queue_t workQueue;

    dispatch_source_t dispatchSource;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        NSError *err;

        // NSFileHandle opened with fileHandleForReadingFromURL ows its associated
        // file descriptor, and will close it automatically when deallocated.
        logFileHandle = [NSFileHandle
          fileHandleForReadingFromURL:[NSURL fileURLWithPath:[sharedDB rotatingLogNoticesPath]]
                                error:&err];

        bytesReadFileOffset = (unsigned long long) 0;

        workQueue = dispatch_queue_create([(APP_GROUP_IDENTIFIER @".LogViewWorkQueue") UTF8String],
          DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Activity Indicator
    activityIndicator = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    [activityIndicator setHidesWhenStopped:TRUE];
    activityIndicator.color = [UIColor blueColor];
    activityIndicator.center = self.view.center;

    [self.view addSubview:activityIndicator];

    // UIBar
    [self setTitle:@"Logs"];

    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc]
      initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(onNavigationDoneTap)];

    UIBarButtonItem *reloadButton = [[UIBarButtonItem alloc]
      initWithTitle:@"Reload" style:UIBarButtonItemStylePlain target:self action:@selector(onReloadTap)];

    [self.navigationItem setRightBarButtonItem:doneButton];
    [self.navigationItem setLeftBarButtonItem:reloadButton];

    [self loadDataAsync:TRUE];

    // Setup listeners for logs file.
    [self setupLogFileListener];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Cancel dispatch source to stop receiving file change notifications.
    if (dispatchSource) {
        dispatch_source_cancel(dispatchSource);
    }
}


#pragma mark - UI Callbacks

- (void)onNavigationDoneTap {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onReloadTap {
    [self loadDataAsync:TRUE];
}

#pragma mark - Helper functions

/*!
 * Submits work to workQueue to read new bytes from the log file an update the tableView.
 * @param userAction Whether a user action initiated data loading.
 */
- (void)loadDataAsync:(BOOL)userAction {

    // Caller should show spinner only when user performs an action.
    if (userAction) {
        [activityIndicator startAnimating];
    }

    dispatch_async(workQueue, ^{

        unsigned long long newBytesReadFileOffset;

        BOOL isFirstLogRead = (bytesReadFileOffset == 0);

        NSString *logData = [PsiphonDataSharedDB tryReadingFile:[sharedDB rotatingLogNoticesPath]
                                                usingFileHanlde:&logFileHandle
                                                 readFromOffset:bytesReadFileOffset
                                                   readToOffset:&newBytesReadFileOffset];

        LOG_DEBUG(@"TEST old file offset %llu", bytesReadFileOffset);
        LOG_DEBUG(@"TEST new file offset %llu", newBytesReadFileOffset);
        LOG_DEBUG(@"TEST bytes read %llu", (newBytesReadFileOffset - bytesReadFileOffset));

        if (logData && ([logData length] > 0)) {

            bytesReadFileOffset = newBytesReadFileOffset;
            NSMutableArray *newEntries = [[NSMutableArray alloc] init];
            [sharedDB readLogsData:logData intoArray:newEntries];

            // On the first load, truncate array entries to MAX_LOGS_LOAD
            if (isFirstLogRead && ([newEntries count] > MAX_LOGS_LOAD)) {
                newEntries = [[NSMutableArray alloc] initWithArray:
                  [newEntries subarrayWithRange:NSMakeRange([newEntries count] - MAX_LOGS_LOAD, MAX_LOGS_LOAD)]];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                // Calculate IndexPaths
                NSUInteger currentNumRows = [self.diagnosticEntries count];
                NSUInteger numRowsToAdd = [newEntries count];
                NSMutableArray *indexPaths = [[NSMutableArray alloc] initWithCapacity:numRowsToAdd];
                for (int i = 0; i < numRowsToAdd; ++i) {
                    [indexPaths addObject:[NSIndexPath indexPathForRow:(i+currentNumRows) inSection:0]];
                }

                // Checks if last row was visible before the update.
                BOOL lastRowWasVisible = isFirstLogRead || [self.tableView.indexPathsForVisibleRows containsObject:
                  [NSIndexPath indexPathForRow:(currentNumRows - 1) inSection:0]];

                [self.tableView beginUpdates];
                [self.diagnosticEntries addObjectsFromArray:newEntries];
                [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationNone];
                [self.tableView endUpdates];

                // Only scroll to bottom if last row before the update
                // was visible on the screen.
                if (lastRowWasVisible || userAction) {
                    [self scrollToBottom];
                }

                if (userAction) {
                    [activityIndicator stopAnimating];
                }
            });
        } else {
            // At this point there was nothing to load,
            // we resort to scrolling to bottom of screen.
            if (userAction) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [activityIndicator stopAnimating];
                    [self scrollToBottom];
                });
            }
        }


    });
}

- (void)setupLogFileListener {
    int fd = open([[sharedDB rotatingLogNoticesPath] UTF8String], O_RDONLY);

    if (fd == -1) {
        LOG_ERROR(@"Error opening log file to watch. errno: %s", strerror(errno));
        [activityIndicator stopAnimating];
        return;
    }

    unsigned long mask = DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE;

    dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t) fd,
      mask, workQueue);

    dispatch_source_set_event_handler(dispatchSource, ^{
        unsigned long flag = dispatch_source_get_data(dispatchSource);

        // TODO: what flag is sent when file is truncated.
        if (flag & DISPATCH_VNODE_WRITE) {
            LOG_DEBUG(@"TEST Dispatch_vnode_write");
            [self loadDataAsync:FALSE];
        } else if (flag & DISPATCH_VNODE_EXTEND){
            LOG_DEBUG(@"TEST Dispatch_vnode_extend");
        } else if (flag & DISPATCH_VNODE_DELETE) {
            LOG_DEBUG(@"TEST Dispatch_vnode_delete");
            bytesReadFileOffset = 0;
            dispatch_source_cancel(dispatchSource);
        }
    });

    dispatch_source_set_cancel_handler(dispatchSource, ^{
        LOG_DEBUG(@"TEST dispatchSource Cancelled");
        close(fd);
    });

    dispatch_resume(dispatchSource);
}

@end
