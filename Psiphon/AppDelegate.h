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
#import "AppEvent.h"

@class RACReplaySubject<ValueType>;
@class RACMulticastConnection<__covariant ValueType>;

/**
 * User's subscription status.
 */
typedef NS_ENUM(NSInteger, UserSubscriptionStatus) {
    /** @const UserSubscriptionUnknown User's subscription status is not known yet (pending). */
    UserSubscriptionUnknown = 1,
    /** @const UserSubscriptionInActive User does not have an active subscription. */
    UserSubscriptionInactive,
    /** @const UserSubscriptionActive User has an active subscription. */
    UserSubscriptionActive
};

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

// appEvents is hot infinite multicasted signal with underlying replay subject.
@property (nonatomic, nullable, readonly) RACMulticastConnection<AppEvent *> *appEvents;

/**
 * subscriptionStatus emits an item of type `UserSubscriptionStatus` wrapped in NSNumber.
 * This replay subject has the initial value of `UserSubscriptionUnknown`.
 *
 * @note This subject might emit non-unique events.
 *
 * @scheduler vpnStartStatus delivers its events on the main thread.
 */
@property (nonatomic, readonly) RACReplaySubject<NSNumber *> *subscriptionStatus;

@property (atomic) BOOL shownLandingPageForCurrentSession;

+ (AppDelegate *)sharedAppDelegate;

- (void)reloadMainViewControllerAndImmediatelyOpenSettings;

- (void)reloadOnboardingViewController;

- (UIAlertController *)displayAlertNoInternet:(void (^_Nullable)(UIAlertAction *))handler;

+ (UIViewController *)getTopMostViewController;

@end
