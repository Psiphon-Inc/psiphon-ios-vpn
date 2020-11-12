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
#import "AdManager.h"
#import "Strings.h"
#import "UIAlertController+Additions.h"
#import "AppObservables.h"
#import "Psiphon-Swift.h"

// Specifier keys for cells in settings menu
// These keys are defined in Psiphon/InAppSettings.bundle/Root.inApp.plist
NSString * const SettingsPsiCashCellSpecifierKey = @"settingsPsiCash";
NSString * const SettingsSubscriptionCellSpecifierKey = @"settingsSubscription";
NSString * const SettingsReinstallVPNConfigurationKey = @"settingsReinstallVPNConfiguration";
NSString * const SettingsResetAdConsentCellSpecifierKey = @"settingsResetAdConsent";
NSString * const SettingsPsiCashAccountLogoutCellSpecifierKey = @"settingsLogOutPsiCashAccount";

@interface SettingsViewController ()
 
@property (nonatomic) BOOL hasActiveSubscription;
@property (nonatomic) VPNStatus vpnStatus;
@property (nonatomic) BOOL isPsiCashAccountLoggedIn;

@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@end

@implementation SettingsViewController {
    UITableViewCell *subscriptionTableViewCell;
    UITableViewCell *reinstallVPNProfileCell;
    UITableViewCell *resetConsentCell;
    UITableViewCell *psiCashAccountLogOutCell;
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

    RACDisposable *tunnelStatusDisposable =
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
    
    [self.compoundDisposable addDisposable:
     [AppObservables.shared.isLoggedInToPsiCashAccount
      subscribeNext:^(NSNumber * _Nullable isLoggedIn) {
        SettingsViewController *__strong strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf.isPsiCashAccountLoggedIn = [isLoggedIn boolValue];
            [strongSelf updateHiddenKeys];
        }
    }]];
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
    
    if (self.isPsiCashAccountLoggedIn == TRUE) {
        [hiddenKeys removeObject:SettingsPsiCashAccountLogoutCellSpecifierKey];
    } else {
        [hiddenKeys addObject:SettingsPsiCashAccountLogoutCellSpecifierKey];
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

    } else if ([specifier.key isEqualToString:SettingsResetAdConsentCellSpecifierKey]) {
        [self onResetConsent];
        NSIndexPath *path = [tableView indexPathForCell:resetConsentCell];
        [tableView deselectRowAtIndexPath:path animated:TRUE];
        
    } else if ([specifier.key isEqualToString:SettingsPsiCashAccountLogoutCellSpecifierKey]) {
        [self onPsiCashAccountLogOut];
        NSIndexPath *path = [tableView indexPathForCell:psiCashAccountLogOutCell];
        [tableView deselectRowAtIndexPath:path animated:TRUE];
    }
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForSpecifier:(IASKSpecifier*)specifier {
    UITableViewCell *cell = nil;

    NSArray<NSString *> *customKeys = @[
      SettingsPsiCashCellSpecifierKey,
      SettingsSubscriptionCellSpecifierKey,
      SettingsReinstallVPNConfigurationKey,
      SettingsResetAdConsentCellSpecifierKey,
      SettingsPsiCashAccountLogoutCellSpecifierKey
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

    } else if ([specifier.key isEqualToString:SettingsResetAdConsentCellSpecifierKey]) {
        cell = [super tableView:tableView cellForSpecifier:specifier];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = self.view.tintColor;
        cell.textLabel.text = [UserStrings Reset_admob_consent];
        resetConsentCell = cell;
        
    } else if ([specifier.key isEqualToString:SettingsPsiCashAccountLogoutCellSpecifierKey]) {
        cell = [super tableView:tableView cellForSpecifier:specifier];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = UIColor.peachyPink;
        cell.textLabel.text = [UserStrings Logout_of_psicash_account];
        psiCashAccountLogOutCell = cell;
    }

    PSIAssert(cell != nil);
    return cell;
}

#pragma mark - Callbacks

- (void)openPsiCashViewController {
    [SwiftDelegate.bridge presentPsiCashViewController:PsiCashScreenTabAddPsiCash];
}

- (void)openIAPViewController {
    IAPViewController *iapViewController = [[IAPViewController alloc]init];
    iapViewController.openedFromSettings = YES;
    [self.navigationController pushViewController:iapViewController animated:YES];
}

- (void)onResetConsent {
    UIAlertController *options = [UIAlertController alertControllerWithTitle:nil
                                                                     message:nil
                                                  preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *resetAction = [UIAlertAction actionWithTitle:[Strings resetConsentButtonTitle]
        style:UIAlertActionStyleDestructive
      handler:^(UIAlertAction *action) {
          [[AdManager sharedInstance] resetUserConsent];
      }];

    [options addAction:resetAction];
    [options addCancelAction:nil];
    [options presentFromTopController];
}

- (void)onPsiCashAccountLogOut {
    UIAlertController *options = [UIAlertController
                                  alertControllerWithTitle:[UserStrings Log_out]
                                  message:[UserStrings Are_you_sure_psicash_account_logout]
                                  preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *resetAction = [UIAlertAction actionWithTitle:[UserStrings Log_out]
                                                          style:UIAlertActionStyleDestructive
                                                        handler:^(UIAlertAction *action) {
        [SwiftDelegate.bridge logOutPsiCashAccount];
    }];
    
    [options addAction:resetAction];
    [options addCancelAction:nil];
    [options presentFromTopController];
}

@end
