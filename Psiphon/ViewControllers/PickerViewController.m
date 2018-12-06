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

#import "PickerViewController.h"
#import "UIView+Additions.h"
#import "UIColor+Additions.h"
#import "ImageUtils.h"
#import "UIFont+Additions.h"
#import "Strings.h"

NSString * const CellIdentifier = @"cell";

@implementation PickerViewController {
    UITableView *pickerTableView;
    NSArray<NSString *> *_Nonnull labels;
    NSArray<UIImage *> *_Nullable images;
}

- (instancetype)initWithLabels:(NSArray<NSString *> *)pickerLabels
                     andImages:(NSArray<UIImage *> *_Nullable)pickerImages {

    self = [super init];
    if (self) {
        labels = pickerLabels;
        images = pickerImages;

        if (images) {
            assert([labels count] == [images count]);
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Navigation bar
    {
        self.navigationController.navigationBar.backgroundColor = UIColor.whiteColor;
        self.navigationController.navigationBar.barTintColor = UIColor.whiteColor;

        // Removes the default iOS bottom border.
        [self.navigationController.navigationBar setValue:@(TRUE) forKeyPath:@"hidesShadow"];

        UIBarButtonItem *doneButton = [[UIBarButtonItem alloc]
          initWithTitle:[Strings doneButtonTitle]
                  style:UIBarButtonItemStyleDone
                 target:self
                 action:@selector(onDone)];
        doneButton.tintColor = UIColor.lightishBlue;
        self.navigationItem.rightBarButtonItem = doneButton;

        self.navigationController.navigationBar.titleTextAttributes = @{
            NSFontAttributeName: [UIFont avenirNextDemiBold:14.f],
            NSForegroundColorAttributeName: UIColor.offWhite
        };
    }

    {
        pickerTableView = [[UITableView alloc] initWithFrame:CGRectZero];
        pickerTableView.separatorStyle = UITableViewCellSeparatorStyleNone;

        pickerTableView.translatesAutoresizingMaskIntoConstraints = FALSE;
        pickerTableView.dataSource = self;
        pickerTableView.delegate = self;
        [self.view addSubview:pickerTableView];

        [NSLayoutConstraint activateConstraints:@[
          [pickerTableView.topAnchor constraintEqualToAnchor:self.view.safeTopAnchor],
          [pickerTableView.bottomAnchor constraintEqualToAnchor:self.view.safeBottomAnchor],
          [pickerTableView.leadingAnchor constraintEqualToAnchor:self.view.safeLeadingAnchor],
          [pickerTableView.trailingAnchor constraintEqualToAnchor:self.view.safeTrailingAnchor],
        ]];
    }
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    
    // Reload table only if it has been loaded.
    if (pickerTableView) {
        [pickerTableView reloadData];
    }
}

#pragma mark - Methods to be used by subclasses

- (NSUInteger)numberOfRows {
    return [labels count];
}

- (void)bindDataToCell:(UITableViewCell *)cell atRow:(NSUInteger)rowIndex {
    cell.textLabel.text = labels[rowIndex];
    if (images) {
        cell.imageView.image = images[rowIndex];
    }
}

- (void)onSelectedRow:(NSUInteger)rowIndex {
    if (self.selectionHandler) {
        self.selectionHandler(rowIndex, nil, self);
    }
}

#pragma mark - UITableViewDataSource delegate methods

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self numberOfRows];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    NSUInteger row = (NSUInteger) indexPath.row;

    UITableViewCell *_Nullable cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:CellIdentifier];

        cell.textLabel.font = [UIFont avenirNextMedium:16.f];
        cell.textLabel.textColor = UIColor.greyishBrown;

        cell.layer.borderWidth = 1.f;
        cell.layer.borderColor = UIColor.paleGrey.CGColor;

        UIImageView *chevronView = [[UIImageView alloc]
          initWithImage:[UIImage imageNamed:@"chevron"]];
        cell.accessoryView = chevronView;

        UIView *backgroundView = [[UIView alloc] initWithFrame:cell.frame];
        cell.selectedBackgroundView = backgroundView;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }

    [self bindDataToCell:cell atRow:row];

    return cell;
}

- (void)tableView:(UITableView *)tableView
      willDisplayCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)indexPath {

    NSUInteger row = (NSUInteger) indexPath.row;

    if (row == self.selectedIndex) {
        cell.selected = TRUE;
        cell.selectedBackgroundView.backgroundColor = UIColor.duckEggBlueTwoColor;
    } else {
        cell.selected = FALSE;
        cell.selectedBackgroundView.backgroundColor = UIColor.whiteColor;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 53.f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger row = (NSUInteger) indexPath.row;
    self.selectedIndex = row;
    [self onSelectedRow:row];
}

#pragma mark - UI callback

- (void)onDone {
    [self dismissViewControllerAnimated:TRUE completion:nil];
}

@end
