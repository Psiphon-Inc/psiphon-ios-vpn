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
#import <SafariServices/SafariServices.h>

// Specifier keys for cells in settings menu
// These keys are defined in Psiphon/InAppSettings.bundle/Root.inApp.plist
NSString * const SettingsSubscriptionCellSpecifierKey = @"settingsSubscription";
NSString * const SettingsReinstallVPNConfigurationKey = @"settingsReinstallVPNConfiguration";

// PsiCash group
NSString * const SettingsPsiCashGroupHeaderTitleKey = @"settingsPsiCashGroupTitle";
NSString * const SettingsPsiCashCellSpecifierKey = @"settingsPsiCash";
NSString * const SettingsPsiCashAccountLogoutCellSpecifierKey = @"settingsLogOutPsiCashAccount";
NSString * const SettingsPsiCashAccountManagementSpecifierKey = @"settingsManagePsiCashAccount";
NSString * const SettingspsiCashAccountLoginCellSpecifierKey = @"settingsLoginPsiCashAccount";

@interface SettingsViewController ()
 
@property (nonatomic) ObjcSettingsViewModel *viewModel;

@property (nonatomic) RACCompoundDisposable *compoundDisposable;

// Set of keys for custom views that are managed by this class (SettingsViewController).
// These cells have type `IASKCustomViewSpecifier`.
// - Note: Some custom views are managed by the super class.
@property (nonatomic) NSArray<NSString *> *customKeys;

@end

@implementation SettingsViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
        
        _customKeys = @[
          SettingsSubscriptionCellSpecifierKey,
          SettingsReinstallVPNConfigurationKey,
          SettingsPsiCashGroupHeaderTitleKey,
          SettingsPsiCashCellSpecifierKey,
          SettingsPsiCashAccountManagementSpecifierKey,
          SettingsPsiCashAccountLogoutCellSpecifierKey,
          SettingspsiCashAccountLoginCellSpecifierKey
        ];
           
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

            [strongSelf updateHiddenKeys];
            [strongSelf.tableView reloadData];
            
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
    // - Not allowed when disconnected (button disabled, not hidden).
    // - Not allowed when logging out
    if (self.viewModel.isPsiCashAccountLoggedIn == TRUE) {
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
    
    // PsiCash Login button:
    // - Shown when not logged in (no tokens, trackers, logged out state)
    // - Not allowed when disconnected (button disabled, not hidden).
    if (self.viewModel.isPsiCashAccountLoggedIn == TRUE) {
        [hiddenKeys addObject:SettingspsiCashAccountLoginCellSpecifierKey];
    } else {
        [hiddenKeys removeObject:SettingspsiCashAccountLoginCellSpecifierKey];
    }
    
    [self setHiddenKeys:hiddenKeys animated:FALSE];
    
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // Navigation bar may have been customized, revert
    self.navigationController.navigationBar.barTintColor = nil;
    self.navigationController.navigationBar.tintColor = nil;
    [self.navigationController.navigationBar setTitleTextAttributes:nil];
}

#pragma mark - Table constructor methods

- (NSString *)settingsViewController:(id<IASKViewController>)settingsViewController
                           tableView:(UITableView *)tableView
            titleForHeaderForSection:(NSInteger)section {
    
    // specifierKey can be nil for section that don't have a key.
    NSString *_Nullable specifierKey = [self.settingsReader keyForSection:section];
    
    if ([self.customKeys containsObject:specifierKey] == FALSE) {
        return nil;
    }
    
    if ([specifierKey isEqualToString:SettingsPsiCashGroupHeaderTitleKey]) {
        return [UserStrings PsiCash];
        
    } else {
        
        // Programming error.
        PSIAssert(FALSE);
        return @"(null)";
        
    }
    
}

- (UITableViewCell *)tableView:(UITableView *)tableView
              cellForSpecifier:(IASKSpecifier *)specifier {
    
    // `self.viewModel` is expected to have a value.
    if (self.viewModel == nil) {
        return nil;
    }
        
    // If custom cell's key is not in `self.customKeys` then
    // it is managed by the superclass.
    if ([self.customKeys containsObject:specifier.key] == FALSE) {
        return [super tableView:tableView cellForSpecifier:specifier];
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:specifier.key];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                      reuseIdentifier:specifier.key];
    }
    
    if ([specifier.key isEqualToString:SettingsSubscriptionCellSpecifierKey]) {
        
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        [cell.textLabel setText:[UserStrings Subscription]];

    } else if ([specifier.key isEqualToString:SettingsReinstallVPNConfigurationKey]) {

        [cell setAccessoryType:UITableViewCellAccessoryNone];
        [cell.textLabel setText:[UserStrings Reinstall_vpn_config]];
                
        BOOL enabled = [VPNStateCompat isDisconnected:self.viewModel.vpnStatus];
        cell.userInteractionEnabled = enabled;
        cell.textLabel.enabled = enabled;
        cell.detailTextLabel.enabled = enabled;

    } else if ([specifier.key isEqualToString:SettingsPsiCashCellSpecifierKey]) {
        // PsiCash button.
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        cell.textLabel.text = [UserStrings PsiCash];
        
    } else if ([specifier.key isEqualToString:SettingsPsiCashAccountManagementSpecifierKey]) {
        // PsiCash Account Management button.
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        [cell.textLabel setText:[UserStrings PsiCash_account_management]];
        
        // PsiCash account management button disabled when not connected,
        // and when logging out.
        BOOL enabled = ([VPNStateCompat isConnected:self.viewModel.vpnStatus] && !self.viewModel.isLoggingOut);
        cell.userInteractionEnabled = enabled;
        cell.textLabel.enabled = enabled;
        cell.detailTextLabel.enabled = enabled;
        
    } else if ([specifier.key isEqualToString:SettingsPsiCashAccountLogoutCellSpecifierKey]) {
        // PsiCash Account Logout button.
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.text = [UserStrings Log_Out];
        
        // Logout button is enabled when VPN state in not in a transitory state.
        BOOL enabled = ![VPNStateCompat isInTransition:self.viewModel.vpnStatus];
        cell.userInteractionEnabled = enabled;
        cell.textLabel.enabled = enabled;
        cell.detailTextLabel.enabled = enabled;
        
    } else if ([specifier.key isEqualToString:SettingspsiCashAccountLoginCellSpecifierKey]) {
        // PsiCash Account Login button.
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.text = [UserStrings Log_in];
        
        // Login button is enabled when VPN state in not in a transitory state.
        BOOL enabled = ![VPNStateCompat isInTransition:self.viewModel.vpnStatus];
        cell.userInteractionEnabled = enabled;
        cell.textLabel.enabled = enabled;
        cell.detailTextLabel.enabled = enabled;
        
    }

    PSIAssert(cell != nil);
    return cell;
    
}

#pragma mark - Selection handler

- (void)settingsViewController:(IASKAppSettingsViewController *)sender
                     tableView:(UITableView *)tableView
  didSelectCustomViewSpecifier:(IASKSpecifier *)specifier {
    
    // If custom cell's key is not in `self.customKeys` then
    // it is managed by the superclass.
    if ([self.customKeys containsObject:specifier.key] == FALSE) {
        
        [super settingsViewController:sender
                            tableView:tableView
         didSelectCustomViewSpecifier:specifier];
        
        return;
    }
    
    // Gets cell for current `specifier.key`.
    NSIndexPath *indexPath = [self.settingsReader indexPathForKey:specifier.key];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    
    // Deselects given cell.
    [tableView deselectRowAtIndexPath:indexPath animated:TRUE];
    
    // Handles selection based on `specifier.key`.
    if ([specifier.key isEqualToString:SettingsSubscriptionCellSpecifierKey]) {
        
        // Subscription button
        [self openIAPViewController];

    } else if ([specifier.key isEqualToString:SettingsReinstallVPNConfigurationKey]) {
        
        // Reinstall VPN config button
        [SwiftDelegate.bridge reinstallVPNConfig];
        [self settingsViewControllerDidEnd:nil];

    } else if ([specifier.key isEqualToString:SettingsPsiCashCellSpecifierKey]) {
        
        // PsiCash button
        [self openPsiCashViewController];
        
    } else if ([specifier.key isEqualToString:SettingsPsiCashAccountManagementSpecifierKey]) {
        
        // PsiCash Account Management button
        [self openPsiCashAccountManagement];
        
    } else if ([specifier.key isEqualToString:SettingsPsiCashAccountLogoutCellSpecifierKey]) {
        
        // PsiCash Account Logout button
        [self onPsiCashAccountLogOutWithSourceView:cell];
        
    } else if ([specifier.key isEqualToString:SettingspsiCashAccountLoginCellSpecifierKey]) {
        
        //PsiCash Account Login button
        [self onPsiCashAccountLoginTapped];
        
    }
    
}

#pragma mark - Callbacks

- (void)openPsiCashViewController {
    [SwiftDelegate.bridge presentPsiCashViewController:PsiCashScreenTabAddPsiCash];
}

- (void)openPsiCashAccountManagement {
    [SwiftDelegate.bridge presentPsiCashAccountManagement];
}

- (void)onPsiCashAccountLoginTapped {
    [SwiftDelegate.bridge presentPsiCashAccountViewControllerWithPsiCashScreen:FALSE];
}

- (void)openIAPViewController {
    IAPViewController *iapViewController = [[IAPViewController alloc]init];
    iapViewController.openedFromSettings = YES;
    [self.navigationController pushViewController:iapViewController animated:YES];
}

- (void)onPsiCashAccountLogOutWithSourceView:(UIView *_Nonnull)sourceView {
    
    // No-op if tunnel is not connected or disconnected.
    if ([VPNStateCompat isInTransition:self.viewModel.vpnStatus] == TRUE) {
        return;
    }
    
    BOOL isOffline = [VPNStateCompat isDisconnected:self.viewModel.vpnStatus];
    
    NSString *message;
    NSString *logoutTitle;
    
    if (isOffline == TRUE) {
        
        message = [UserStrings PsiCash_logout_offline_body];
        logoutTitle = [UserStrings Logout_anyway];
        
    } else {
        
        message = [UserStrings Are_you_sure_psicash_account_logout];
        logoutTitle = [UserStrings Log_Out];
        
    }
    
    UIAlertController *alert = [UIAlertController
                                alertControllerWithTitle:[UserStrings Psicash_account_logout_title]
                                message:message
                                preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *logoutAction = [UIAlertAction actionWithTitle:logoutTitle
                                                           style:UIAlertActionStyleDestructive
                                                         handler:^(UIAlertAction *action) {
        [SwiftDelegate.bridge logOutPsiCashAccount];
    }];
    
    // Adds a "Connect" button if tunnel is not connected,
    // and sets it as the default action.
    if (isOffline == TRUE) {
        
        UIAlertAction *connectAction = [UIAlertAction actionWithTitle:[UserStrings Connect]
                                                               style:UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction *action) {
            [SwiftDelegate.bridge connectButtonTappedFromSettings];
        }];
        
        [alert addAction:connectAction];
        
        alert.preferredAction = connectAction;
        
    }
    
    [alert addAction:logoutAction];
    [alert addCancelAction:nil];
    
    [[alert popoverPresentationController] setSourceView:sourceView];
    [[alert popoverPresentationController] setSourceRect:CGRectMake(0,0,1,1)];
    [[alert popoverPresentationController]
     setPermittedArrowDirections:UIPopoverArrowDirectionDown];

    [alert presentFromTopController];
}

@end
