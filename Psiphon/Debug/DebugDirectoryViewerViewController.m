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

#import "DebugDirectoryViewerViewController.h"
#import "Asserts.h"
#import "DispatchUtils.h"
#import "DebugTextViewController.h"

NSString * const FileCellIdentifier = @"FileCell";

@implementation DebugDirectoryViewerViewController {
    NSURL *directory;
    NSString *title;

    NSArray<NSURL *> *files;
    UITableView *fileTableView;
}

+ (instancetype)createAndLoadDirectory:(NSURL *)directory withTitle:(NSString *)title {
    DebugDirectoryViewerViewController *ins = [[DebugDirectoryViewerViewController alloc] init];
    ins->directory = directory;
    ins->title = title;
    return ins;
}

+ (NSArray<NSURL *> *)getFilesAt:(NSURL *)dir {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSError *e;
    NSArray<NSURL *> *dirContents = [fm contentsOfDirectoryAtURL:dir
      includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                           error:&e];

    // Skips objects that are not regular files.
    NSMutableArray<NSURL *> *files = [NSMutableArray arrayWithCapacity:dirContents.count];
    [dirContents enumerateObjectsUsingBlock:^(NSURL *obj, NSUInteger idx, BOOL *stop) {
        NSError *err;
        NSNumber *isRegularFile;
        [obj getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:&err];
        if ([isRegularFile boolValue]) {
            [files addObject:obj];
        }
    }];

    return files;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    files = [DebugDirectoryViewerViewController getFilesAt:directory];

    // Navigation bar
    self.title = title;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                 target:self
                                 action:@selector(dismiss)];

    fileTableView = [[UITableView alloc] init];
    fileTableView.dataSource = self;
    fileTableView.delegate = self;
    [fileTableView registerClass:UITableViewCell.class forCellReuseIdentifier:FileCellIdentifier];
    fileTableView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:fileTableView];

    // Layout constraints
    fileTableView.translatesAutoresizingMaskIntoConstraints = FALSE;
    [fileTableView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = TRUE;
    [fileTableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = TRUE;
    [fileTableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = TRUE;
    [fileTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = TRUE;
}

- (void)dismiss {
    [self dismissViewControllerAnimated:TRUE completion:nil];
}

#pragma mark - UITableViewDataSource delegate methods

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (files.count == 0) {
        return 1;
    }
    return files.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:FileCellIdentifier
                                                            forIndexPath:indexPath];
    cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.textLabel.numberOfLines = 0;

    if (files.count == 0) {
        cell.textLabel.text = [NSString stringWithFormat:@"No files at %@", directory.path];
        return cell;
    }
    
    NSURL *fileURL = files[(NSUInteger) indexPath.row];
    cell.tag = indexPath.row;
    cell.textLabel.text = fileURL.lastPathComponent;

    UITapGestureRecognizer *gr = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(showFileContents:)];
    [cell addGestureRecognizer:gr];

    return cell;
}

- (void)showFileContents:(UITapGestureRecognizer *)sender {
    NSInteger index = sender.view.tag;
    NSURL *fileURL = files[(NSUInteger) index];

    DebugTextViewController *wvc = [DebugTextViewController createAndLoadFileURL:fileURL];
    [self.navigationController pushViewController:wvc animated:TRUE];
}

@end
