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
#import "AppDelegate.h"
#import "IAPViewController.h"
#import "RACSignal.h"
#import "RACCompoundDisposable.h"
#import "RACReplaySubject.h"
#import "Asserts.h"
#import "Strings.h"
#import "UIAlertController+Additions.h"
#import "AppObservables.h"
#import "Psiphon-Swift.h"

// Specifier keys for cells in settings menu
// These keys are defined in Psiphon/InAppSettings.bundle/Root.inApp.plist
NSString * const SettingsPsiCashCellSpecifierKey = @"settingsPsiCash";
NSString * const SettingsSubscriptionCellSpecifierKey = @"settingsSubscription";
NSString * const SettingsReinstallVPNConfigurationKey = @"settingsReinstallVPNConfiguration";

@interface SettingsViewController ()

@property (assign) BOOL hasActiveSubscription;
@property (assign) VPNStatus vpnStatus;

@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@end

@implementation SettingsViewController {
    UITableViewCell *subscriptionTableViewCell;
    UITableViewCell *reinstallVPNProfileCell;
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

    __block RACDisposable *subscriptionStatusDisposable = [AppObservables.shared.subscriptionStatus
      subscribeNext:^(BridgedUserSubscription *status) {

        SettingsViewController *__strong strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf.hasActiveSubscription = (status.state == BridgedSubscriptionStateActive);
            [strongSelf updateHiddenKeys];
        }
      } error:^(NSError *error) {
          SettingsViewController *__strong strongSelf = weakSelf;
          if (strongSelf) {
              [strongSelf.compoundDisposable removeDisposable:subscriptionStatusDisposable];
          }
      } completed:^{
          SettingsViewController *__strong strongSelf = weakSelf;
          if (strongSelf) {
              [strongSelf.compoundDisposable removeDisposable:subscriptionStatusDisposable];
          }
      }];

    [self.compoundDisposable addDisposable:subscriptionStatusDisposable];

    __block RACDisposable *tunnelStatusDisposable =
      [AppObservables.shared.vpnStatus
        subscribeNext:^(NSNumber *statusObject) {
          SettingsViewController *__strong strongSelf = weakSelf;
          if (strongSelf) {
              strongSelf.vpnStatus = (VPNStatus) [statusObject integerValue];
              [strongSelf updateReinstallVPNProfileCell];
              [strongSelf updateHiddenKeys];
          }
        }];

    [self.compoundDisposable addDisposable:tunnelStatusDisposable];
}

- (void)updateHiddenKeys {
    NSMutableSet *hiddenKeys = [NSMutableSet setWithSet:self.hiddenKeys];

    // If the VPN is not active, don't show the force reconnect button.
    if ([VPNStateCompat providerNotStoppedWithVpnStatus:self.vpnStatus]) {
        [hiddenKeys removeObject:kForceReconnect];
        [hiddenKeys removeObject:kForceReconnectFooter];
    } else {
        [hiddenKeys addObject:kForceReconnect];
        [hiddenKeys addObject:kForceReconnectFooter];
    }

    self.hiddenKeys = hiddenKeys;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // Navigation bar may have been customized, revert
    self.navigationController.navigationBar.barTintColor = nil;
    self.navigationController.navigationBar.tintColor = nil;
    [self.navigationController.navigationBar setTitleTextAttributes:nil];
}

#pragma mark - UI update methods

- (void)updateReinstallVPNProfileCell {
    if (reinstallVPNProfileCell) {
        BOOL enableReinstallVPNProfileCell = self.vpnStatus == VPNStatusDisconnected || self.vpnStatus == VPNStatusInvalid;
        reinstallVPNProfileCell.userInteractionEnabled = enableReinstallVPNProfileCell;
        reinstallVPNProfileCell.textLabel.enabled = enableReinstallVPNProfileCell;
        reinstallVPNProfileCell.detailTextLabel.enabled = enableReinstallVPNProfileCell;
    }
}

#pragma mark - Table constructor methods

- (void)settingsViewController:(IASKAppSettingsViewController*)sender
                     tableView:(UITableView *)tableView
    didSelectCustomViewSpecifier:(IASKSpecifier*)specifier {

    [super settingsViewController:self tableView:tableView didSelectCustomViewSpecifier:specifier];

    if ([specifier.key isEqualToString:SettingsPsiCashCellSpecifierKey]) {
        [self openPsiCashViewController];

    } else if ([specifier.key isEqualToString:SettingsSubscriptionCellSpecifierKey]) {
        [self openIAPViewController];

    } else if ([specifier.key isEqualToString:SettingsReinstallVPNConfigurationKey]) {
        [SwiftDelegate.bridge reinstallVPNConfig];
        [self settingsViewControllerDidEnd:nil];

    }
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForSpecifier:(IASKSpecifier*)specifier {
    UITableViewCell *cell = nil;

    NSArray<NSString *> *customKeys = @[
      SettingsPsiCashCellSpecifierKey,
      SettingsSubscriptionCellSpecifierKey,
      SettingsReinstallVPNConfigurationKey,
    ];

    if (![customKeys containsObject:specifier.key]) {
        cell = [super tableView:tableView cellForSpecifier:specifier];
        return cell;
    }

    if ([specifier.key isEqualToString:SettingsPsiCashCellSpecifierKey]) {
        cell = [super tableView:tableView cellForSpecifier:specifier];
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        cell.textLabel.text = [UserStrings PsiCash];

    } else if ([specifier.key isEqualToString:SettingsSubscriptionCellSpecifierKey]) {
        cell = [super tableView:tableView cellForSpecifier:specifier];
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        subscriptionTableViewCell = cell;
        [subscriptionTableViewCell.textLabel setText:[UserStrings Subscription]];

    } else if ([specifier.key isEqualToString:SettingsReinstallVPNConfigurationKey]) {

        cell = [super tableView:tableView cellForSpecifier:specifier];
        [cell setAccessoryType:UITableViewCellAccessoryNone];
        [cell.textLabel setText:[UserStrings Reinstall_vpn_config]];
        reinstallVPNProfileCell = cell;
        [self updateReinstallVPNProfileCell];

    }

    PSIAssert(cell != nil);
    return cell;
}

#pragma mark - Callbacks

- (void)openPsiCashViewController {
    UIViewController *psiCashViewController = [SwiftDelegate.bridge
                                               makePsiCashViewController:PsiCashViewControllerTabsAddPsiCash];
    [self presentViewController:psiCashViewController animated:YES completion:nil];
}

- (void)openIAPViewController {
    IAPViewController *iapViewController = [[IAPViewController alloc]init];
    iapViewController.openedFromSettings = YES;
    [self.navigationController pushViewController:iapViewController animated:YES];
}

@end
