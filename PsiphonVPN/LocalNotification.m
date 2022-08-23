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

#import <UserNotifications/UserNotifications.h>
#import "LocalNotification.h"
#import "VPNStrings.h"
#import "Strings.h"

// UserNotifications identifiers.
NSString *_Nonnull const NotificationIdOpenContainer = @"OpenContainer";
NSString *_Nonnull const NotificationIdCorruptSettings = @"CorruptSettings";
NSString *_Nonnull const NotificationIdSubscriptionExpired = @"SubscriptionExpired";
NSString *_Nonnull const NotificationIdRegionUnavailable = @"RegionUnavailable";
NSString *_Nonnull const NotificationIdUpstreamProxyError = @"UpstreamProxyError";
NSString *_Nonnull const NotificationIdDisallowedTraffic = @"DisallowedTraffic";
NSString *_Nonnull const NotificationIdMustStartVPNFromApp = @"MustStartVPNFromApp";
NSString *_Nonnull const NotificationIdPurchaseRequired = @"PurchaseRequired";

@implementation LocalNotification

+ (void)requestOpenContainerToConnectNotification {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [VPNStrings psiphon];
    content.body = [VPNStrings openPsiphonAppToFinishConnecting];
    
    UNNotificationRequest *request = [UNNotificationRequest
                                      requestWithIdentifier:NotificationIdOpenContainer
                                      content:content
                                      trigger:nil];
    
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        // TODO: log the errors?
        // Do nothing;
    }];
}

+ (void)requestCorruptSettingsFileNotification {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [VPNStrings psiphon];
    content.body = [VPNStrings corruptSettingsFileAlertMessage];
    
    UNNotificationRequest *request = [UNNotificationRequest
                                      requestWithIdentifier:NotificationIdCorruptSettings
                                      content:content
                                      trigger:nil];
    
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        // Do nothing;
    }];
}

+ (void)requestSubscriptionExpiredNotification {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [VPNStrings psiphon];
    content.body = [VPNStrings subscriptionExpiredAlertMessage];
    
    UNNotificationRequest *request = [UNNotificationRequest
                                      requestWithIdentifier:NotificationIdSubscriptionExpired
                                      content:content
                                      trigger:nil];
    
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        // Do nothing;
    }];
}

+ (void)requestSelectedRegionUnavailableNotification {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [VPNStrings psiphon];
    content.body = [Strings selectedRegionUnavailableAlertBody];
    
    
    UNNotificationRequest *request = [UNNotificationRequest
                                      requestWithIdentifier:NotificationIdRegionUnavailable
                                      content:content
                                      trigger:nil];
    
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        // Do nothing;
    }];
}

+ (void)requestUpstreamProxyErrorNotification:(NSString *)message {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [VPNStrings psiphon];
    content.body = [NSString stringWithFormat:@"%@\n\n(%@)",
                    VPNStrings.upstreamProxySettingsErrorMessage, message];
    
    UNNotificationRequest *request = [UNNotificationRequest
                                      requestWithIdentifier:NotificationIdUpstreamProxyError
                                      content:content
                                      trigger:nil];
    
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        // Do nothing;
    }];
}

+ (void)requestDisallowedTrafficNotification {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [VPNStrings disallowed_traffic_notification_title];
    content.body = [VPNStrings disallowed_traffic_alert_notification_body];
    
    UNNotificationRequest *request = [UNNotificationRequest
                                      requestWithIdentifier:NotificationIdDisallowedTraffic
                                      content:content
                                      trigger:nil];
    
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        // Do nothing;
    }];
}

+ (void)requestCannotStartWithoutActiveSubscription {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [VPNStrings psiphon];
    content.body = [VPNStrings mustStartVPNFromApp];
    
    UNNotificationRequest *request = [UNNotificationRequest
                                      requestWithIdentifier:NotificationIdMustStartVPNFromApp
                                      content:content
                                      trigger:nil];
    
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        // Do nothing;
    }];
}

+ (void)requestPurchaseRequiredPrompt {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [VPNStrings psiphon];
    content.body = [VPNStrings purchaseRequiredNotificationMessage];
    
    UNNotificationRequest *request = [UNNotificationRequest
                                      requestWithIdentifier:NotificationIdPurchaseRequired
                                      content:content
                                      trigger:nil];
    
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        // Do nothing;
    }];
}

@end
