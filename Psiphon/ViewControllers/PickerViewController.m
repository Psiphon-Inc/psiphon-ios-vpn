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
#import "Psiphon-Swift.h"

NSString * const CellIdentifier = @"cell";

@interface PickerViewController ()

@property (nonatomic, readwrite) NSLocale *locale;

@end

@implementation PickerViewController {
    UITableView *pickerTableView;
    NSArray<NSString *> *_Nonnull labels;
    NSArray<UIImage *> *_Nullable images;
}

- (instancetype)initWithLabels:(NSArray<NSString *> *)pickerLabels
                     andImages:(NSArray<UIImage *> *_Nullable)pickerImages
                        locale:(NSLocale *)locale {

    self = [super init];
    if (self) {
        labels = pickerLabels;
        images = pickerImages;
        self.locale = locale;

        if (images) {
            assert([labels count] == [images count]);
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.darkBlueColor;

    // Navigation bar
    {
        
        // Apply Psiphon navigation bar styling.
        [self.navigationController.navigationBar applyPsiphonNavigationBarStyling];

        UIBarButtonItem *doneButton = [[UIBarButtonItem alloc]
          initWithTitle:[UserStrings Done_button_title]
                  style:UIBarButtonItemStyleDone
                 target:self
                 action:@selector(onDone)];
        doneButton.tintColor = UIColor.whiteColor;
        self.navigationItem.rightBarButtonItem = doneButton;

    }

    {
        pickerTableView = [[UITableView alloc] initWithFrame:CGRectZero];
        pickerTableView.backgroundColor = UIColor.clearColor;
        pickerTableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        pickerTableView.separatorColor = UIColor.denimBlueColor;

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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Scrolls to selected item after views are laid out, expects self.selectedIndex
    // has already been set.
    // Any earlier, and the correct offset will not have been calculated.
    NSIndexPath *selectedPath = [NSIndexPath indexPathForItem:self.selectedIndex inSection:0];
    [pickerTableView scrollToRowAtIndexPath:selectedPath
                           atScrollPosition:UITableViewScrollPositionMiddle
                                   animated:FALSE];
    
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

- (void)reloadTableRows {
    [pickerTableView reloadData];
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

        cell.backgroundColor = UIColor.clearColor;

        cell.textLabel.font = [UIFont avenirNextMedium:16.f];
        cell.textLabel.textColor = UIColor.greyishBrown;
        
        if (cell.semanticContentAttribute == UISemanticContentAttributeForceRightToLeft) {
            cell.textLabel.textAlignment = NSTextAlignmentRight;
        }

        cell.separatorInset = UIEdgeInsetsZero;

        UIImageView *chevronView = [[UIImageView alloc]
          initWithImage:[UIImage imageNamed:@"Checkmark"]];
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
        cell.textLabel.textColor = UIColor.greyishBrown;
        cell.selectedBackgroundView.backgroundColor = UIColor.duckEggBlueTwoColor;
        cell.accessoryView.hidden = FALSE;
    } else {
        cell.selected = FALSE;
        cell.textLabel.textColor = UIColor.whiteColor;
        cell.selectedBackgroundView.backgroundColor = UIColor.clearColor;
        cell.accessoryView.hidden = TRUE;
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
