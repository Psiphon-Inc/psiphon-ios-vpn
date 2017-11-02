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
        NSString *subscriptionItemTitle;
        if([[IAPHelper sharedInstance]hasActiveSubscriptionForDate:[NSDate date]]) {
            subscriptionItemTitle = NSLocalizedStringWithDefaultValue(@"SETTINGS_SUBSCRIPTION_ACTIVE",
                                                                      nil,
                                                                      [NSBundle mainBundle],
                                                                      @"Subscriptions",
                                                                      @"Subscriptions item title in the app settings when user has an active subscription. Clicking this item opens subscriptions view");
        } else {
            subscriptionItemTitle = NSLocalizedStringWithDefaultValue(@"SETTINGS_SUBSCRIPTION_NOT_ACTIVE",
                                                                      nil,
                                                                      [NSBundle mainBundle],
                                                                      @"Go premium!",
                                                                      @"Subscriptions item title in the app settings when user does not have an active subscription. Clicking this item opens subscriptions view. If “Premium” doesn't easily translate, please choose a term that conveys “Pro” or “Extra” or “Better” or “Elite”.");
        }
        [cell.textLabel setText:subscriptionItemTitle];
    }

    return cell;
}

- (void) openIAPViewController {
    IAPViewController *iapViewController = [[IAPViewController alloc]init];
    iapViewController.openedFromSettings = YES;
    [self.navigationController pushViewController:iapViewController animated:YES];
}

@end
