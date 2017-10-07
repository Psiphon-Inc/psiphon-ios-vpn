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

// Maximum number logs to display.
#define MAX_LOGS_DISPLAY 250

/*
 * Limitations:
 *      - Only the main rotating_notices log file is read and monitored for changes.
 *      - File change monitoring fails if file the log file has not been created yet.
 *
 */
@implementation LogViewControllerFullScreen {
    PsiphonDataSharedDB *sharedDB;

    unsigned long long bytesReadFileOffset;

    // TODO: need to truncate entries if it becomes too large.
    NSMutableArray<DiagnosticEntry *> *entries;

    dispatch_queue_t workQueue;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        bytesReadFileOffset = (unsigned long long) 0;
        entries = [[NSMutableArray alloc] init];

        workQueue = dispatch_queue_create([(APP_GROUP_IDENTIFIER @".LogViewWorkQueue") UTF8String],
          DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // UIBar
    [self setTitle:NSLocalizedStringWithDefaultValue(@"LOGS_TITLE", nil, [NSBundle mainBundle], @"Logs", @"Log view title bar text")];

    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc]
      initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(onNavigationDoneTap)];

    UIBarButtonItem *reloadButton = [[UIBarButtonItem alloc]
      initWithTitle:@"Reload" style:UIBarButtonItemStylePlain target:self action:@selector(onReloadTap)];


    [self.navigationItem setRightBarButtonItem:doneButton];
    [self.navigationItem setLeftBarButtonItem:reloadButton];

    [self loadDataAsync];

    // Setup listeners for logs file.
    [self setupLogFileListener];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

#pragma mark - UI Callbacks

- (void)onNavigationDoneTap {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onReloadTap {
    [self loadDataAsync];
}

#pragma mark - Helper functions

- (void)loadDataAsync {
    dispatch_async(workQueue, ^{

        unsigned long long newBytesReadFileOffset;

        NSString *logData = [PsiphonDataSharedDB tryReadingFile:[sharedDB rotatingLogNoticesPath]
                                                     fromOffset:bytesReadFileOffset
                                                   offsetInFile:(&newBytesReadFileOffset)];

        LOG_DEBUG(@"TEST old file offset %llu", bytesReadFileOffset);
        LOG_DEBUG(@"TEST new file offset %llu", newBytesReadFileOffset);
        LOG_DEBUG(@"TEST bytes read %llu", (newBytesReadFileOffset - bytesReadFileOffset));

        if (logData) {

            bytesReadFileOffset = newBytesReadFileOffset;

            [sharedDB readLogsData:logData intoArray:entries];

            if ([entries count] > MAX_LOGS_DISPLAY) {
                self.diagnosticEntries = [entries
                  subarrayWithRange:NSMakeRange([entries count] - MAX_LOGS_DISPLAY, MAX_LOGS_DISPLAY)];
            } else {
                self.diagnosticEntries = entries;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self onDataChanged];
            });
        }
    });
}

- (void)setupLogFileListener {
    int fd = open([[sharedDB rotatingLogNoticesPath] UTF8String], O_RDONLY);

    if (fd == -1) {
        LOG_ERROR(@"Error opening log file to watch. errno: %s", strerror(errno));
        return;
    }

    unsigned long mask = DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE;

    __block dispatch_source_t dispatchSource;

//    dispatch_queue_t globalQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t) fd,
      mask, workQueue);

    dispatch_source_set_event_handler(dispatchSource, ^{
        unsigned long flag = dispatch_source_get_data(dispatchSource);

        if (flag & DISPATCH_VNODE_WRITE) {
            LOG_DEBUG(@"TEST Dispatch_vnode_write");
            [self loadDataAsync];
        } else if (flag & DISPATCH_VNODE_EXTEND){
            LOG_DEBUG(@"TEST Dispatch_vnode_extend");
        } else if (flag & DISPATCH_VNODE_DELETE) {
            LOG_DEBUG(@"TEST Dispatch_vnode_delete");
            bytesReadFileOffset = 0;
//            dispatch_source_cancel(dispatchSource);
        }
    });

    dispatch_source_set_cancel_handler(dispatchSource, ^{
        LOG_DEBUG(@"TEST dispatchSource Cancelled");
        close(fd);
    });

    dispatch_resume(dispatchSource);
}

@end
