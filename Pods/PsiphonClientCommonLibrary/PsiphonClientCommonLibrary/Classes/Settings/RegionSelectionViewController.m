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

#import "PsiphonClientCommonLibraryHelpers.h"
#import "RegionAdapter.h"
#import "RegionSelectionViewController.h"
#import "UIImage+CountryFlag.h"

@implementation RegionSelectionViewController {
    NSString *selectedRegion;
    NSArray *regions;
    NSInteger selectedRow;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    regions = [[RegionAdapter sharedInstance] getRegions];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.delegate = self;
    self.table.dataSource = self;
    self.table.separatorInset = UIEdgeInsetsMake(0, 0, 0, 0);

    self.table.tableHeaderView = nil;
    self.table.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    [self.view addSubview:self.table];

    // Setup autolayout
    self.table.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.table
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.topLayoutGuide
                                                          attribute:NSLayoutAttributeTop
                                                         multiplier:1.0
                                                           constant:0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.table
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.table
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.0
                                                           constant:0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.table
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:0]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateAvailableRegions:) name:kPsiphonAvailableRegionsNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super viewWillDisappear:animated];
}

#pragma mark - UITableView delegate methods

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    Region *r = [regions objectAtIndex:indexPath.row];

    NSString *identifier = [NSString stringWithFormat:@"%@", r.code];

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }

    cell.imageView.image = [[PsiphonClientCommonLibraryHelpers imageFromCommonLibraryNamed:r.flagResourceId] countryFlag];
    cell.textLabel.text = [[RegionAdapter sharedInstance] getLocalizedRegionTitle:r.code];

    // RTL text alignment override
    if([UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) {
        cell.textLabel.textAlignment = NSTextAlignmentRight;
    }

    cell.userInteractionEnabled = YES;
    cell.hidden = !r.serverExists;

    if ([r.code isEqualToString:[[RegionAdapter sharedInstance] getSelectedRegion].code]) {
        selectedRow = indexPath.row;
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // New region was selected update tableview cells

    // De-select cell of currently selected region
    NSUInteger currentIndex[2];
    currentIndex[0] = 0;
    currentIndex[1] = selectedRow;
    NSIndexPath *currentIndexPath = [[NSIndexPath alloc] initWithIndexes:currentIndex length:2];
    UITableViewCell *currentlySelectedCell = [tableView cellForRowAtIndexPath:currentIndexPath];
    currentlySelectedCell.accessoryType = UITableViewStylePlain; // Remove checkmark

    // Select cell of newly chosen region
    Region *r = [regions objectAtIndex:indexPath.row];
    selectedRow = indexPath.row;
    selectedRegion = r.code;
    [[RegionAdapter sharedInstance] setSelectedRegion:selectedRegion];

    NSIndexPath *newIndexPath = [tableView indexPathForSelectedRow];
    UITableViewCell *newlySelectedCell = [tableView cellForRowAtIndexPath:newIndexPath];
    newlySelectedCell.accessoryType = UITableViewCellAccessoryCheckmark;
    [tableView deselectRowAtIndexPath:newIndexPath animated:YES];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    Region *r = [regions objectAtIndex:indexPath.row];
    return r.serverExists ? 44.0f : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return regions.count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

#pragma mark - Notifications

- (void) updateAvailableRegions:(NSNotification*) notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.table reloadData];
    });
}

@end
