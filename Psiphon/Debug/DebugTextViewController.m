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

#import "DebugTextViewController.h"
#import "PsiFeedbackLogger.h"
#import "NSDate+PSIDateExtension.h"

@implementation DebugTextViewController {
    NSURL *url;
    UITextView *textView;
}

+ (instancetype)createAndLoadFileURL:(NSURL *)url {
    DebugTextViewController *ins = [[DebugTextViewController alloc] init];
    ins->url = url;
    return ins;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Navigation bar
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                 target:self
                                 action:@selector(dismiss)];

    textView = [[UITextView alloc] init];
    [self.view addSubview:textView];

    textView.translatesAutoresizingMaskIntoConstraints = FALSE;
    [textView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = TRUE;
    [textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = TRUE;
    [textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = TRUE;
    [textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = TRUE;

    NSString *data;
    NSError *err;

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[[url filePathURL] path] error:&err];

    if (err != nil) {
        data = [[PsiFeedbackLogger unpackError:err] debugDescription];
    } else {
        self.title = [((NSDate *)attrs[NSFileModificationDate]) RFC3339MilliString];
        data = [[NSString alloc] initWithData:[NSData dataWithContentsOfURL:url] encoding:NSUTF8StringEncoding];
    }

    textView.text = data;
}

- (void)dismiss {
    [self dismissViewControllerAnimated:TRUE completion:nil];
}

@end
