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
#import "VPNManager.h"

@interface SettingsViewController ()
@end

@implementation SettingsViewController {
    UISwitch *vpnOnDemandToggle;
}

- (void)viewWillAppear:(BOOL)animated {
    if([IAPHelper canMakePayments] == NO) {
        self.hiddenKeys = [[NSSet alloc] initWithArray:@[kSettingsSubscription]];
    }
    // Observe IAP transaction notification
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updatedIAPTransactionState)
                                                 name:kIAPSKPaymentTransactionStatePurchased
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updatedIAPTransactionState)
                                                 name:kIAPSKPaymentQueuePaymentQueueRestoreCompletedTransactionsFinished
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updatedIAPTransactionState)
                                                 name:kIAPSKPaymentQueueRestoreCompletedTransactionsFailedWithError
                                               object:nil];

    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kIAPSKPaymentTransactionStatePurchased object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kIAPSKPaymentQueuePaymentQueueRestoreCompletedTransactionsFinished object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kIAPSKPaymentQueueRestoreCompletedTransactionsFailedWithError object:nil];
    [super viewWillDisappear:animated];
}

- (void)settingsViewController:(IASKAppSettingsViewController*)sender tableView:(UITableView *)tableView didSelectCustomViewSpecifier:(IASKSpecifier*)specifier {
    [super settingsViewController:self tableView:tableView didSelectCustomViewSpecifier:specifier];
    if ([specifier.key isEqualToString:kSettingsSubscription]) {
        [self openIAPViewController];
    }
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForSpecifier:(IASKSpecifier*)specifier {
    UITableViewCell *cell = nil;
    if (![specifier.key isEqualToString:kSettingsSubscription] && ![specifier.key isEqualToString:kVpnOnDemand]) {
        cell = [super tableView:tableView cellForSpecifier:specifier];
        return cell;
    }

    BOOL hasActiveSubscription = [[IAPHelper sharedInstance]hasActiveSubscriptionForDate:[NSDate date]];
    if ([specifier.key isEqualToString:kSettingsSubscription]) {
        cell = [super tableView:tableView cellForSpecifier:specifier];
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        NSString *subscriptionItemTitle;
        if(hasActiveSubscription) {
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
                                                                      @"Subscriptions item title in the app settings when user does not have an active subscription. Clicking this item opens subscriptions view");
        }
        [cell.textLabel setText:subscriptionItemTitle];

    } else if ([specifier.key isEqualToString:kVpnOnDemand]) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryView = [[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 79, 27)];
        vpnOnDemandToggle = (UISwitch*)cell.accessoryView;
        [vpnOnDemandToggle addTarget:self action:@selector(toggledVpnOnDemandValue:) forControlEvents:UIControlEventValueChanged];

        cell.textLabel.text = NSLocalizedStringWithDefaultValue(@"SETTINGS_VPN_ON_DEMAND",
                                                                     nil,
                                                                     [NSBundle mainBundle],
                                                                     @"Auto-start VPN on demand",
                                                                     @"Automatically start VPN On demand settings toggle");


        NSString *subscriptionOnlySubtitle;
        if(!hasActiveSubscription) {
            vpnOnDemandToggle.on = NO;
            cell.userInteractionEnabled = NO;
            cell.textLabel.enabled = NO;
            cell.detailTextLabel.enabled = NO;
            subscriptionOnlySubtitle = NSLocalizedStringWithDefaultValue(@"SETTINGS_VPN_ON_DEMAND_DETAIL",
                                                                      nil,
                                                                      [NSBundle mainBundle],
                                                                      @"Subscription only",
                                                                      @"VPN On demand setting detail text showing when user doesn't have an active subscription and the item is disabled.");
        } else {
            vpnOnDemandToggle.on = [[VPNManager sharedInstance] isVPNConfigurationOnDemandEnabled];
            cell.userInteractionEnabled = YES;
            cell.textLabel.enabled = YES;
            subscriptionOnlySubtitle = @"";
        }

        cell.detailTextLabel.text = subscriptionOnlySubtitle;
    }

    assert(cell != nil);
    return cell;
}

- (void)toggledVpnOnDemandValue:(id)sender {
    UISwitch *toggle = (UISwitch*)sender;

    __weak SettingsViewController *weakSelf = self;
    [[VPNManager sharedInstance] updateVPNConfigurationOnDemandSetting:[toggle isOn]
                                                     completionHandler:^(NSError *error, BOOL changeSaved) {

        [weakSelf.tableView reloadData];
    }];
}

- (void) openIAPViewController {
    IAPViewController *iapViewController = [[IAPViewController alloc]init];
    iapViewController.openedFromSettings = YES;
    [self.navigationController pushViewController:iapViewController animated:YES];
}

- (void) updatedIAPTransactionState {
    [self.tableView reloadData];
}

@end
