/*
 * Copyright (c) 2020, Psiphon Inc.
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

@interface VPNStrings : NSObject

// Simple alert message when user notification cannot be displayed.
+ (NSString *)disallowed_traffic_simple_alert_message;

+ (NSString *)disallowed_traffic_notification_title;

+ (NSString *)disallowed_traffic_alert_notification_body;

+ (NSString *)corruptSettingsFileAlertMessage;

+ (NSString *)cannotStartTunnelDueToSubscription;

+ (NSString *)openPsiphonAppToFinishConnecting;

+ (NSString *)upstreamProxySettingsErrorMessage;

+ (NSString *)subscriptionExpiredAlertMessage;

@end

NS_ASSUME_NONNULL_END
