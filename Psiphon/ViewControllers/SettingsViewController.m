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
#import "RACSignal+Operations.h"
#import "Asserts.h"
#import "Strings.h"
#import "UIAlertController+Additions.h"
#import "AppObservables.h"
#import "Psiphon-Swift.h"
#import "Logging.h"
#import <SafariServices/SafariServices.h>

// Specifier keys for cells in settings menu
// These keys are defined in Psiphon/InAppSettings.bundle/Root.inApp.plist
NSString * const SettingsSubscriptionCellSpecifierKey = @"settingsSubscription";
NSString * const SettingsReinstallVPNConfigurationKey = @"settingsReinstallVPNConfiguration";
NSString * const SettingsResetAdConsentCellSpecifierKey = @"settingsResetAdConsent";

// PsiCash group
NSString * const SettingsPsiCashHeaderTitleKey = @"settingsPsiCashGroupTitle";
NSString * const SettingsPsiCashCellSpecifierKey = @"settingsPsiCash";
NSString * const SettingsPsiCashAccountLogoutCellSpecifierKey = @"settingsLogOutPsiCashAccount";
NSString * const SettingsPsiCashAccountManagementSpecifierKey = @"settingsManagePsiCashAccount";

@interface SettingsViewController ()
 
@property (nonatomic) ObjcSettingsViewModel *viewModel;

@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@end

@implementation SettingsViewController {
    UITableViewCell *_Nullable subscriptionTableViewCell;
    UITableViewCell *_Nullable reinstallVPNProfileCell;
    UITableViewCell *_Nullable resetConsentCell;
    UITableViewCell *_Nullable psiCashCell;
    UITableViewCell *_Nullable psiCashAccountManagementCell;
    UITableViewCell *_Nullable psiCashAccountLogOutCell;
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
    
    [self.compoundDisposable addDisposable:
     [[AppObservables.shared.settingsViewModel
      deliverOnMainThread]
      subscribeNext:^(ObjcSettingsViewModel * _Nullable viewModel) {
        
        // Self can only be mutated on the main thread.
        SettingsViewController *__strong strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf.viewModel = viewModel;
            [strongSelf updateReinstallVPNProfileCell];
            [strongSelf updateHiddenKeys];
        }
        
    }]];
}

- (void)updateHiddenKeys {
    
    if (self.viewModel == nil) {
        return;
    }
    
    NSMutableSet *hiddenKeys = [NSMutableSet setWithSet:self.hiddenKeys];

    // If the VPN is not active, don't show the force reconnect button.
    if ([VPNStateCompat providerNotStoppedWithVpnStatus:self.viewModel.vpnStatus]) {
        [hiddenKeys removeObject:kForceReconnect];
        [hiddenKeys removeObject:kForceReconnectFooter];
    } else {
        [hiddenKeys addObject:kForceReconnect];
        [hiddenKeys addObject:kForceReconnectFooter];
    }
    
    // PsiCash Manage Account button:
    // - Shown when logged in account.
    // - Not allowed when disconnected.
    if (self.viewModel.isPsiCashAccountLoggedIn == TRUE &&
        [VPNStateCompat isConnected:self.viewModel.vpnStatus] == TRUE) {
        [hiddenKeys removeObject:SettingsPsiCashAccountManagementSpecifierKey];
    } else {
        [hiddenKeys addObject:SettingsPsiCashAccountManagementSpecifierKey];
    }
    
    // PsiCash Logout button:
    // - Shown when logged in account.
    // - Allowed when disconnected, local only, with prompt.
    if (self.viewModel.isPsiCashAccountLoggedIn == TRUE) {
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
    if (reinstallVPNProfileCell != nil && self.viewModel != nil) {
        VPNStatus s = self.viewModel.vpnStatus;
        BOOL enabled = (s == VPNStatusDisconnected || s == VPNStatusInvalid);
        
        reinstallVPNProfileCell.userInteractionEnabled = enabled;
        reinstallVPNProfileCell.textLabel.enabled = enabled;
        reinstallVPNProfileCell.detailTextLabel.enabled = enabled;
    }
}

#pragma mark - Table constructor methods

- (void)settingsViewController:(IASKAppSettingsViewController*)sender
                     tableView:(UITableView *)tableView
    didSelectCustomViewSpecifier:(IASKSpecifier*)specifier {

    [super settingsViewController:self tableView:tableView didSelectCustomViewSpecifier:specifier];

    if ([specifier.key isEqualToString:SettingsSubscriptionCellSpecifierKey]) {
        [self openIAPViewController];

    } else if ([specifier.key isEqualToString:SettingsReinstallVPNConfigurationKey]) {
        [SwiftDelegate.bridge reinstallVPNConfig];
        [self settingsViewControllerDidEnd:nil];

    } else if ([specifier.key isEqualToString:SettingsResetAdConsentCellSpecifierKey]) {
        [self onResetConsent];
        NSIndexPath *path = [tableView indexPathForCell:resetConsentCell];
        [tableView deselectRowAtIndexPath:path animated:TRUE];
        
    } else if ([specifier.key isEqualToString:SettingsPsiCashCellSpecifierKey]) {
        // PsiCash button
        [self openPsiCashViewController];
        NSIndexPath *path = [tableView indexPathForCell:psiCashCell];
        [tableView deselectRowAtIndexPath:path animated:TRUE];
        
    } else if ([specifier.key isEqualToString:SettingsPsiCashAccountManagementSpecifierKey]) {
        [self openPsiCashAccountManagement];
        NSIndexPath *path = [tableView indexPathForCell:psiCashAccountManagementCell];
        [tableView deselectRowAtIndexPath:path animated:TRUE];
        
    } else if ([specifier.key isEqualToString:SettingsPsiCashAccountLogoutCellSpecifierKey]) {
        [self onPsiCashAccountLogOut];
        NSIndexPath *path = [tableView indexPathForCell:psiCashAccountLogOutCell];
        [tableView deselectRowAtIndexPath:path animated:TRUE];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
 
    // For header titles that are customzied in this class (SettingsViewController),
    // it's value is expected to be the key of the header that is customized.
    NSString *value = [super tableView:tableView titleForHeaderInSection:section];
    
    if ([value isEqualToString:SettingsPsiCashHeaderTitleKey]) {
        // PsiCash header.
        return [UserStrings PsiCash];
    } else {
        return value;
    }
    
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForSpecifier:(IASKSpecifier*)specifier {
    UITableViewCell *cell = nil;

    // List of cells created by this class (SettingsViewController).
    NSArray<NSString *> *customKeys = @[
      SettingsSubscriptionCellSpecifierKey,
      SettingsReinstallVPNConfigurationKey,
      SettingsResetAdConsentCellSpecifierKey,
      SettingsPsiCashCellSpecifierKey,
      SettingsPsiCashAccountManagementSpecifierKey,
      SettingsPsiCashAccountLogoutCellSpecifierKey
    ];

    // Returns cell from superclass if the specifier.key
    // is not in the customKeys list.
    if ([customKeys containsObject:specifier.key] == FALSE) {
        cell = [super tableView:tableView cellForSpecifier:specifier];
        return cell;
    }

    if ([specifier.key isEqualToString:SettingsSubscriptionCellSpecifierKey]) {
        
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
        
    } else if ([specifier.key isEqualToString:SettingsPsiCashCellSpecifierKey]) {
        // PsiCash button.
        cell = [super tableView:tableView cellForSpecifier:specifier];
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        cell.textLabel.text = [UserStrings PsiCash];
        psiCashCell = cell;
        
    } else if ([specifier.key isEqualToString:SettingsPsiCashAccountManagementSpecifierKey]) {
        // PsiCash Account Management button.
        cell = [super tableView:tableView cellForSpecifier:specifier];
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        [cell.textLabel setText:[UserStrings PsiCash_account_management]];
        psiCashAccountManagementCell = cell;
        
    } else if ([specifier.key isEqualToString:SettingsPsiCashAccountLogoutCellSpecifierKey]) {
        // PsiCash Account Logout button.
        cell = [super tableView:tableView cellForSpecifier:specifier];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.text = [UserStrings Log_out];
        psiCashAccountLogOutCell = cell;
    }

    PSIAssert(cell != nil);
    return cell;
}

#pragma mark - Callbacks

- (void)openPsiCashViewController {
    [SwiftDelegate.bridge presentPsiCashViewController:PsiCashScreenTabAddPsiCash];
}

- (void)openPsiCashAccountManagement {
    
    NSURL *url = self.viewModel.accountManagementURL;
    if (url == nil) {
        return;
    }
    
    SFSafariViewController *ctrl = [[SFSafariViewController alloc] initWithURL:url];
    
    [self presentViewController:ctrl animated:TRUE completion:^{
        // No-op.
    }];
    
}

- (void)openIAPViewController {
    IAPViewController *iapViewController = [[IAPViewController alloc]init];
    iapViewController.openedFromSettings = YES;
    [self.navigationController pushViewController:iapViewController animated:YES];
}

- (void)onResetConsent {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                     message:nil
                                                  preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *resetAction = [UIAlertAction actionWithTitle:[Strings resetConsentButtonTitle]
        style:UIAlertActionStyleDestructive
      handler:^(UIAlertAction *action) {
          [SwiftDelegate.bridge resetAdConsent];
      }];

    [alert addAction:resetAction];
    [alert addCancelAction:nil];

    [[alert popoverPresentationController] setSourceView:resetConsentCell];
    [[alert popoverPresentationController] setSourceRect:CGRectMake(0,0,1,1)];
    [[alert popoverPresentationController]
     setPermittedArrowDirections:UIPopoverArrowDirectionDown];

    [alert presentFromTopController];
}

- (void)onPsiCashAccountLogOut {
    UIAlertController *alert = [UIAlertController
                                alertControllerWithTitle:[UserStrings Log_out]
                                message:[UserStrings Are_you_sure_psicash_account_logout]
                                preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *logoutAction = [UIAlertAction actionWithTitle:[UserStrings Log_out]
                                                           style:UIAlertActionStyleDestructive
                                                         handler:^(UIAlertAction *action) {
        [SwiftDelegate.bridge logOutPsiCashAccount];
    }];
    
    [alert addAction:logoutAction];
    [alert addCancelAction:nil];

    [[alert popoverPresentationController] setSourceView:psiCashAccountLogOutCell];
    [[alert popoverPresentationController] setSourceRect:CGRectMake(0,0,1,1)];
    [[alert popoverPresentationController]
     setPermittedArrowDirections:UIPopoverArrowDirectionDown];

    [alert presentFromTopController];
}

@end
