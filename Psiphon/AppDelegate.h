/*
 * Copyright (c) 2015, Psiphon Inc.
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

// Subscription notifications
FOUNDATION_EXPORT NSNotificationName const AppDelegateSubscriptionDidExpireNotification;
FOUNDATION_EXPORT NSNotificationName const AppDelegateSubscriptionDidActivateNotification;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

+ (AppDelegate *)sharedAppDelegate;
+ (BOOL)isFirstRunOfAppVersion;
+ (BOOL)isRunningUITest;

/* Ads */
- (UIViewController *)getAdsPresentingViewController;
- (void)launchScreenFinished;

/**
 * Reloads the MainViewController.
 *
 * @details
 * reloadMainViewController is meant to be used after a settings change (e.g. default language).
 */
- (void)reloadMainViewController;

+ (UIViewController *)getTopMostViewController;

@end
