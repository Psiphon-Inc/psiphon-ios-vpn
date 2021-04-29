/*
 * Copyright (c) 2016, Psiphon Inc.
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


#import <UIKit/UIKit.h>
#import <InAppSettingsKit/IASKAppSettingsViewController.h>
#import "FeedbackViewController.h"
#import "PsiphonClientCommonLibraryConstants.h"

//app language key
#define appLanguage	@"appLanguage"

// Globally used specifier keys
#define kRegionSelectionSpecifierKey	@"regionSelection"
#define kDisableTimeouts				@"disableTimeouts"
#define kForceReconnect					@"forceReconnect"
#define kForceReconnectFooter			@"forceReconnectFooter"

@protocol PsiphonSettingsViewControllerDelegate <FeedbackViewControllerDelegate>
- (void)notifyPsiphonConnectionState;
- (void)reloadAndOpenSettings;
- (void)settingsWillDismissWithForceReconnect:(BOOL)forceReconnect;
@optional
- (BOOL)shouldEnableSettingsLinks;
- (NSArray<NSString*>*)hiddenSpecifierKeys;
@end

@interface PsiphonSettingsViewController : IASKAppSettingsViewController <UITableViewDelegate, IASKSettingsDelegate, UIAlertViewDelegate>
@property (strong, nonatomic) NSDictionary *preferencesSnapshot;
@property (weak, nonatomic) id<PsiphonSettingsViewControllerDelegate> settingsDelegate;
- (UITableViewCell*)tableView:(UITableView*)tableView cellForSpecifier:(IASKSpecifier*)specifier;
@end

