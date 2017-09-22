//
//  SettingsViewController.m
//  Psiphon
//
//  Created by eugene-imac on 2017-09-18.
//  Copyright © 2017 Psiphon Inc. All rights reserved.
//

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
	IAPViewController * iapViewController = [[IAPViewController alloc]init];
	iapViewController.openedFromSettings = YES;
	[self.navigationController pushViewController:iapViewController animated:YES];
}

@end
