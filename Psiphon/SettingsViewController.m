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

#import "SettingsViewController.h"
#import "IAPHelper.h"
#import "IAPViewController.h"

@interface SettingsViewController ()

@end

@implementation SettingsViewController

- (void)viewWillAppear:(BOOL)animated {
	if([IAPHelper canMakePayments] == NO) {
		self.hiddenKeys = [[NSSet alloc] initWithArray:@[kSettingsSubscription]];
	}
	[super viewWillAppear:animated];
}

- (void)settingsViewController:(IASKAppSettingsViewController*)sender tableView:(UITableView *)tableView didSelectCustomViewSpecifier:(IASKSpecifier*)specifier {
	[super settingsViewController:self tableView:tableView didSelectCustomViewSpecifier:specifier];
	if ([specifier.key isEqualToString:kSettingsSubscription]) {
		[self openIAPViewController];
	}
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForSpecifier:(IASKSpecifier*)specifier {
	UITableViewCell *cell = [super tableView:tableView cellForSpecifier:specifier];

	if ([specifier.key isEqualToString:kSettingsSubscription]) {
		[cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
		[cell.textLabel setText:specifier.title];
	}

	return cell;
}

- (void) openIAPViewController {
	IAPViewController *iapViewController = [[IAPViewController alloc]init];
	iapViewController.openedFromSettings = YES;
	[self.navigationController pushViewController:iapViewController animated:YES];
}

@end
