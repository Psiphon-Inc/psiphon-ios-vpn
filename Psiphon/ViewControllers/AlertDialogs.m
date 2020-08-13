/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import "AlertDialogs.h"
#import "Strings.h"
#import "Psiphon-Swift.h"


@implementation AlertDialogs

+ (UIAlertController *)vpnPermissionDeniedAlert {
    // Alert the user that their permission is required in order to install the VPN configuration.
    UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:[Strings permissionRequiredAlertTitle]
                       message:[Strings vpnPermissionDeniedAlertMessage]
                preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *privacyPolicyAction = [UIAlertAction
      actionWithTitle:[Strings privacyPolicyButtonTitle]
                style:UIAlertActionStyleDefault
              handler:^(UIAlertAction *action) {

         NSString *urlString = [Strings privacyPolicyURLString];
         [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString]
                                            options:@{}
                                  completionHandler:^(BOOL success) {
                                      // Do nothing.
                                  }];
     }];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:[UserStrings Dismiss_button_title]
                                                            style:UIAlertActionStyleCancel
                                                          handler:^(UIAlertAction *action) {
                                                              // Do nothing.
                                                          }];

    [alert addAction:privacyPolicyAction];
    [alert addAction:dismissAction];

    return alert;
}

+ (UIAlertController *)genericOperationFailedTryAgain {
    UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:[Strings operationFailedAlertTitle]
                       message:[UserStrings Operation_failed_alert_message]
                preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:[UserStrings Dismiss_button_title]
                                                            style:UIAlertActionStyleCancel
                                                          handler:^(UIAlertAction *action) {
                                                              // Do nothing.
                                                          }];

    [alert addAction:dismissAction];

    return alert;
}

@end
