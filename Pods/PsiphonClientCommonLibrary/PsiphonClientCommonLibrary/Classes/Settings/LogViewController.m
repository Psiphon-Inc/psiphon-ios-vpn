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

#import "LogViewController.h"

@implementation LogViewController {
    /// Data source
    NSMutableArray<DiagnosticEntry*> *diagnosticEntries;

    /// Entries to display after applying the search filter
    NSMutableArray<DiagnosticEntry*> *displayedEntries;

    /// Search
    UITextField *searchBar;
    UIButton *caseSensitiveButton;
    BOOL caseSensitiveSearchEnabled;
    NSString *searchFilter;
    NSLayoutConstraint *tableViewBottomConstraint;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (@available(iOS 13.0, *)) {
        [self.view setBackgroundColor:UIColor.secondarySystemBackgroundColor];
    } else {
        // Fallback on earlier versions
        [self.view setBackgroundColor:UIColor.whiteColor];
    }
    [self registerForKeyboardNotifications];

    self->diagnosticEntries = [[NSMutableArray alloc] init];
    self->displayedEntries = [[NSMutableArray alloc] init];

    // Case sensitive search button

    self->caseSensitiveButton = [[UIButton alloc] init];
    [self.view addSubview:self->caseSensitiveButton];

    [self->caseSensitiveButton setTitle:@"Aa" forState:UIControlStateNormal];
    if (@available(iOS 13.0, *)) {
        [self->caseSensitiveButton setTitleColor:UIColor.quaternaryLabelColor forState:UIControlStateNormal];
        [self->caseSensitiveButton setTitleColor:UIColor.labelColor forState:UIControlStateSelected];
    } else {
        [self->caseSensitiveButton setTitleColor:UIColor.lightGrayColor forState:UIControlStateNormal];
        [self->caseSensitiveButton setTitleColor:UIColor.blackColor forState:UIControlStateSelected];
    }
    [self->caseSensitiveButton setAlpha:0.74];
    self->caseSensitiveButton.translatesAutoresizingMaskIntoConstraints = NO;

    [self->caseSensitiveButton addTarget:self
                      action:@selector(onCaseSensitivePressed:)
            forControlEvents:UIControlEventTouchUpInside];

    // Search Bar

    self->searchBar = [[UITextField alloc] init];
    [self.view addSubview:self->searchBar];

    self->searchBar.font = [UIFont systemFontOfSize:15];
    if (@available(iOS 13.0, *)) {
        self->searchBar.textColor = UIColor.labelColor;
    } else {
        // Fallback on earlier versions
        self->searchBar.textColor = UIColor.blackColor;
    }
    self->searchBar.placeholder = @"search";
    self->searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self->searchBar.keyboardType = UIKeyboardTypeDefault;
    self->searchBar.returnKeyType = UIReturnKeyDone;
    self->searchBar.clearButtonMode = UITextFieldViewModeWhileEditing;
    self->searchBar.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;

    [self->searchBar setReturnKeyType:UIReturnKeyDone];
    self->searchBar.delegate = self;

    // TableView
    self.tableView = [[UITableView alloc] init];
    [self.view addSubview:self.tableView];

    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.estimatedRowHeight = 60;
    self.tableView.rowHeight = UITableViewAutomaticDimension;

    // Button

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self->caseSensitiveButton
                                                          attribute:NSLayoutAttributeHeight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self->searchBar
                                                          attribute:NSLayoutAttributeHeight
                                                         multiplier:1.f
                                                           constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self->caseSensitiveButton
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.f
                                                           constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self->caseSensitiveButton
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self->searchBar
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.f
                                                           constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self->caseSensitiveButton
                                                          attribute:NSLayoutAttributeWidth
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:nil
                                                          attribute:NSLayoutAttributeNotAnAttribute
                                                         multiplier:1.f
                                                           constant:50]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self->caseSensitiveButton
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeTopMargin
                                                         multiplier:1.f
                                                           constant:0]];

    // Search bar autolayout

    self->searchBar.translatesAutoresizingMaskIntoConstraints = FALSE;

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self->searchBar
                                                          attribute:NSLayoutAttributeHeight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:nil
                                                          attribute:NSLayoutAttributeNotAnAttribute
                                                         multiplier:1.f
                                                           constant:50]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self->searchBar
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self->caseSensitiveButton
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.f
                                                           constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self->searchBar
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.f
                                                           constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self->searchBar
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeTopMargin
                                                         multiplier:1.f
                                                           constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self->searchBar
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.tableView
                                                          attribute:NSLayoutAttributeTop
                                                         multiplier:1.f
                                                           constant:0]];

    // TableView autolayout

    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.tableView
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.f
                                                           constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.tableView
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.f
                                                           constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.tableView
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self->searchBar
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.f
                                                           constant:0]];

    self->tableViewBottomConstraint = [NSLayoutConstraint constraintWithItem:self.tableView
                                                                   attribute:NSLayoutAttributeBottom
                                                                   relatedBy:NSLayoutRelationEqual
                                                                      toItem:self.view
                                                                   attribute:NSLayoutAttributeBottomMargin
                                                                  multiplier:1.f
                                                                    constant:0];
    [self.view addConstraint:self->tableViewBottomConstraint];
}

#pragma mark - Helper methods

-(void)scrollToBottom {
    @synchronized (self) {
        if ([self->displayedEntries count] > 0) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self->displayedEntries count] - 1 inSection:0];
            [self.tableView scrollToRowAtIndexPath:indexPath
                                  atScrollPosition:UITableViewScrollPositionTop
                                          animated:FALSE];
        }
    }
}

- (BOOL)lastRowVisible {
    NSUInteger currentNumRows = [self->displayedEntries count];
    return [self.tableView.indexPathsForVisibleRows containsObject:
            [NSIndexPath indexPathForRow:(currentNumRows - 1) inSection:0]];
}

- (void)addEntries:(NSArray<DiagnosticEntry *> *)newEntries {
    @synchronized (self) {

        // Filter entries based on search bar input
        NSArray <DiagnosticEntry*>* newFilteredEntries = [LogViewController filterEntries:newEntries
                                                                               withFilter:self->searchFilter
                                                                         andCaseSensitive:self->caseSensitiveSearchEnabled];

        NSUInteger currentNumRows = [self->displayedEntries count];

        // Calculate IndexPaths
        NSUInteger numRowsToAdd = [newFilteredEntries count];
        NSMutableArray *indexPaths = [[NSMutableArray alloc] initWithCapacity:numRowsToAdd];
        for (int i = 0; i < numRowsToAdd; ++i) {
            [indexPaths addObject:[NSIndexPath indexPathForRow:(i+currentNumRows) inSection:0]];
        }

        [self->diagnosticEntries addObjectsFromArray:newEntries];
        [self->displayedEntries addObjectsFromArray:newFilteredEntries];

        [self.tableView beginUpdates];
        [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView endUpdates];
    }
}


#pragma mark - Keyboard events

- (void)registerForKeyboardNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(keyboardWillShow:)
            name:UIKeyboardWillShowNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
             selector:@selector(keyboardWillHide:)
             name:UIKeyboardWillHideNotification object:nil];
}


- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];

    CGRect frame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect newFrame = [self.view convertRect:frame fromView:[[UIApplication sharedApplication] delegate].window];

    self->tableViewBottomConstraint.constant = newFrame.origin.y - CGRectGetHeight(self.view.frame) + self.view.layoutMargins.bottom;
    [self.view layoutIfNeeded];

    [self scrollToBottom];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self->tableViewBottomConstraint.constant = 0;
    [self.view layoutIfNeeded];
}

# pragma mark - Search

+ (NSArray<DiagnosticEntry *> *)filterEntries:(NSArray<DiagnosticEntry*>*)entries
                                   withFilter:(NSString*)filter
                             andCaseSensitive:(BOOL)caseSensitive {

    if (filter && [filter length] > 0) {
        return [entries
                filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DiagnosticEntry *_Nonnull entry, NSDictionary<NSString *,id> * _Nullable bindings) {
            if (caseSensitive) {
                return [entry.message containsString:filter];
            }
            return [entry.message rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound;
        }]];
    }

    return entries;
}

#pragma mark - UITextField delegate methods (search bar)

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    // Dismiss keyboard when "Done" is pressed.
    [self->searchBar resignFirstResponder];
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField {
    @synchronized (self) {
        self->searchFilter = nil;
        self->displayedEntries = self->diagnosticEntries;
        [self.tableView reloadData];
        [self scrollToBottom];
    }
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    @synchronized (self) {

        NSString *newSearchFilter = [self->searchBar.text stringByReplacingCharactersInRange:range
                                                                                  withString:string];
        NSArray *entriesToSearch;

        if (self->searchFilter && [self->searchFilter length] > 0) {

            NSRange range = [newSearchFilter rangeOfString:self->searchFilter];

            if (range.location == 0 && range.length == [self->searchFilter length]) {
                // Performance:
                // Only search the displayed entries because the new search filter is a
                // concatenation of the previous one.
                entriesToSearch = self->displayedEntries;
            } else {
                entriesToSearch = self->diagnosticEntries;
            }
        } else {
            entriesToSearch = self->diagnosticEntries;
        }

        if (entriesToSearch && [entriesToSearch count] > 0) {
            self->displayedEntries = [NSMutableArray arrayWithArray:
                                      [LogViewController filterEntries:entriesToSearch
                                                            withFilter:newSearchFilter
                                                      andCaseSensitive:self->caseSensitiveSearchEnabled]];
        }

        self->searchFilter = newSearchFilter;

        [self.tableView reloadData];
        [self scrollToBottom];
    }

    return YES;
}

- (void)onCaseSensitivePressed:(UIButton *)button {
    self->caseSensitiveSearchEnabled = !self->caseSensitiveSearchEnabled;
    self->displayedEntries = [NSMutableArray arrayWithArray:
                              [LogViewController filterEntries:self->diagnosticEntries
                                                    withFilter:self->searchFilter
                                              andCaseSensitive:self->caseSensitiveSearchEnabled]];
    [button setSelected:self->caseSensitiveSearchEnabled];
    [self.tableView reloadData];
    [self scrollToBottom];
}

#pragma mark - UITableView delegate methods

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self->displayedEntries count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DiagnosticEntry *entry = self->displayedEntries[indexPath.row];

    NSMutableAttributedString *attrTextForDisplay = [[NSMutableAttributedString alloc]
      initWithString:[NSString stringWithFormat:@"%@  ", [entry getTimestampForDisplay]]
          attributes:@{NSForegroundColorAttributeName: [UIColor blueColor],
                       NSFontAttributeName: [UIFont fontWithName:@"Helvetica" size:10.f]}];

    NSDictionary *emoNoticeMapping = @{
        @"Tunnels: {\"count\":1}": @"🚀",
        @"Homepage": @"🏡",
        @"Info": @"ℹ️",
        @"Alert": @"🚨",
        @"ActiveTunnel": @"🚇"
    };

    NSDictionary *messageAttr = @{NSFontAttributeName: [UIFont fontWithName:@"Helvetica" size:12.f]};
    NSString *displayMessage = [entry message];

    for (NSString *key in emoNoticeMapping) {
        if (([[entry message] length] >= [key length])
            && ([[[entry message] substringToIndex:[key length]] isEqualToString:key])) {
            displayMessage = [NSString stringWithFormat:@"%@ %@", emoNoticeMapping[key], [entry message]];
        }
    }

    NSMutableAttributedString *attrEntryMessage = [[NSMutableAttributedString alloc]
      initWithString:displayMessage
          attributes:messageAttr];

    [attrTextForDisplay appendAttributedString:attrEntryMessage];

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"reusableCell"];

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"reusableCell"];
    }

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.font = [UIFont fontWithName:@"Helvetica" size:12.0f];
    cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.attributedText = attrTextForDisplay;

    return cell;
}

@end
