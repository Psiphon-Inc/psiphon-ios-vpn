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
#import "IAPStoreHelper.h"
#import "IAPViewController.h"
#import "VPNManager.h"
#import "AppDelegate.h"
#import "RACSignal.h"
#import "RACCompoundDisposable.h"
#import "RACReplaySubject.h"
#import "RACSignal+Operations.h"

// NSUserDefaults keys
/**
 * SettingsConnectOnDemandBoolKey represents user's preference for Connect On Demand.
 * This preference should not be displayed to the user directly, and only the VPN configuration
 * saved Connect On Demand value should be displayed to user.
 */
UserDefaultsKey const SettingsConnectOnDemandBoolKey = @"SettingsViewController.ConnectOnDemandKey";

// Specifier keys for cells in settings menu
// These keys are defined in Psiphon/InAppSettings.bundle/Root.inApp.plist
NSString * const SettingsSubscriptionCellSpecifierKey = @"settingsSubscription";
NSString * const ConnectOnDemandCellSpecifierKey = @"vpnOnDemand";

@interface SettingsViewController ()

@property (assign) BOOL hasActiveSubscription;

@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@end

@implementation SettingsViewController {

    // Subscription row
    UITableViewCell *subscriptionTableViewCell;

    // Connect On Demand row
    UISwitch *connectOnDemandToggle;
    UITableViewCell *connectOnDemandCell;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
    }
    return self;
}

- (void)dealloc {
    [self.compoundDisposable dispose];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    __weak SettingsViewController *weakSelf = self;

    __block RACDisposable *disposable = [[AppDelegate sharedAppDelegate].subscriptionStatus
      subscribeNext:^(NSNumber *value) {
          UserSubscriptionStatus s = (UserSubscriptionStatus) [value integerValue];

          weakSelf.hasActiveSubscription = (s == UserSubscriptionActive);
          [weakSelf updateSubscriptionUIElements];

      } error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];

}

- (void)viewWillAppear:(BOOL)animated {

    if(![IAPStoreHelper canMakePayments]) {
        self.hiddenKeys = [[NSSet alloc] initWithArray:@[SettingsSubscriptionCellSpecifierKey]];
    }

    [super viewWillAppear:animated];
}

#pragma mark - UI update methods

- (void)updateSubscriptionUIElements {
    [self updateSubscriptionCell];
    [self updateConnectOnDemandCell];
}

- (void)updateSubscriptionCell {
    NSString *subscriptionCellTitle;
    if (self.hasActiveSubscription) {
        subscriptionCellTitle = NSLocalizedStringWithDefaultValue(@"SETTINGS_SUBSCRIPTION_ACTIVE",
          nil,
          [NSBundle mainBundle],
          @"Subscriptions",
          @"Subscriptions item title in the app settings when user has an active subscription. Clicking this item opens subscriptions view");
    } else {
        subscriptionCellTitle = NSLocalizedStringWithDefaultValue(@"SETTINGS_SUBSCRIPTION_NOT_ACTIVE",
          nil,
          [NSBundle mainBundle],
          @"Go premium!",
          @"Subscriptions item title in the app settings when user does not have an active subscription. Clicking this item opens subscriptions view. If “Premium” doesn't easily translate, please choose a term that conveys “Pro” or “Extra” or “Better” or “Elite”.");
    }

    [subscriptionTableViewCell.textLabel setText:subscriptionCellTitle];
}

- (void)updateConnectOnDemandCell {
    NSString *subscriptionOnlySubtitle;
    if(!self.hasActiveSubscription) {
        connectOnDemandToggle.on = NO;
        connectOnDemandCell.userInteractionEnabled = NO;
        connectOnDemandCell.textLabel.enabled = NO;
        connectOnDemandCell.detailTextLabel.enabled = NO;
        subscriptionOnlySubtitle = NSLocalizedStringWithDefaultValue(@"SETTINGS_VPN_ON_DEMAND_DETAIL",
          nil,
          [NSBundle mainBundle],
          @"Subscription only",
          @"VPN On demand setting detail text showing when user doesn't have an active subscription and the item is disabled.");
    } else {

        __weak SettingsViewController *weakSelf = self;

        __block RACDisposable *disposable = [[[[VPNManager sharedInstance] isConnectOnDemandEnabled]
          deliverOnMainThread]
          subscribeNext:^(NSNumber *enabled) {
              connectOnDemandToggle.on = [enabled boolValue];
          } error:^(NSError *error) {
              [weakSelf.compoundDisposable removeDisposable:disposable];
          } completed:^{
              [weakSelf.compoundDisposable removeDisposable:disposable];
          }];

        [self.compoundDisposable addDisposable:disposable];


        connectOnDemandCell.userInteractionEnabled = YES;
        connectOnDemandCell.textLabel.enabled = YES;
        subscriptionOnlySubtitle = @"";
    }

    connectOnDemandCell.detailTextLabel.text = subscriptionOnlySubtitle;
}

#pragma mark - Table constuctor methods

- (void)settingsViewController:(IASKAppSettingsViewController*)sender tableView:(UITableView *)tableView didSelectCustomViewSpecifier:(IASKSpecifier*)specifier {
    [super settingsViewController:self tableView:tableView didSelectCustomViewSpecifier:specifier];
    if ([specifier.key isEqualToString:SettingsSubscriptionCellSpecifierKey]) {
        [self openIAPViewController];
    }
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForSpecifier:(IASKSpecifier*)specifier {
    UITableViewCell *cell = nil;
    if (![specifier.key isEqualToString:SettingsSubscriptionCellSpecifierKey] && ![specifier.key isEqualToString:ConnectOnDemandCellSpecifierKey]) {
        cell = [super tableView:tableView cellForSpecifier:specifier];
        return cell;
    }

    if ([specifier.key isEqualToString:SettingsSubscriptionCellSpecifierKey]) {

        cell = [super tableView:tableView cellForSpecifier:specifier];
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        subscriptionTableViewCell = cell;
        [self updateSubscriptionCell];

    } else if ([specifier.key isEqualToString:ConnectOnDemandCellSpecifierKey]) {

        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryView = [[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 79, 27)];
        connectOnDemandToggle = (UISwitch*)cell.accessoryView;
        [connectOnDemandToggle addTarget:self action:@selector(toggledVpnOnDemandValue:) forControlEvents:UIControlEventValueChanged];

        cell.textLabel.text = NSLocalizedStringWithDefaultValue(@"SETTINGS_VPN_ON_DEMAND",
                                                                nil,
                                                                [NSBundle mainBundle],
                                                                @"Auto-start VPN on demand",
                                                                @"Automatically start VPN On demand settings toggle");
        connectOnDemandCell = cell;
        [self updateConnectOnDemandCell];
    }

    assert(cell != nil);
    return cell;
}

- (void)toggledVpnOnDemandValue:(id)sender {
    UISwitch *toggle = (UISwitch*)sender;

    [[NSUserDefaults standardUserDefaults] setBool:[toggle isOn] forKey:SettingsConnectOnDemandBoolKey];

    __weak SettingsViewController *weakSelf = self;

    __block RACDisposable *disposable = [[[[VPNManager sharedInstance]
      setConnectOnDemandEnabled:[toggle isOn]]
      deliverOnMainThread]
      subscribeNext:^(NSNumber *success) {
          [weakSelf updateConnectOnDemandCell];
      } error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }   completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];
}

- (void)openIAPViewController {
    IAPViewController *iapViewController = [[IAPViewController alloc]init];
    iapViewController.openedFromSettings = YES;
    [self.navigationController pushViewController:iapViewController animated:YES];
}

@end
