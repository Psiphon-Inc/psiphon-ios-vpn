/*
 * Copyright (c) 2022, Psiphon Inc.
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *_Nonnull const NotificationIdOpenContainer;
extern NSString *_Nonnull const NotificationIdCorruptSettings;
extern NSString *_Nonnull const NotificationIdSubscriptionExpired;
extern NSString *_Nonnull const NotificationIdRegionUnavailable;
extern NSString *_Nonnull const NotificationIdUpstreamProxyError;
extern NSString *_Nonnull const NotificationIdDisallowedTraffic;
extern NSString *_Nonnull const NotificationIdMustStartVPNFromApp;
extern NSString *_Nonnull const NotificationIdPurchaseRequired;

#if TARGET_IS_EXTENSION
// NE notification service.
@interface LocalNotificationService : NSObject

+ (instancetype)shared;

- (void)requestOpenContainerToConnectNotification;

- (void)requestCorruptSettingsFileNotification;

- (void)requestSubscriptionExpiredNotification;

- (void)requestSelectedRegionUnavailableNotification;

- (void)requestUpstreamProxyErrorNotification:(NSString *)message;

- (void)requestDisallowedTrafficNotification;

- (void)requestCannotStartWithoutActiveSubscription;

- (void)requestPurchaseRequiredPrompt;

@end
#endif

NS_ASSUME_NONNULL_END
