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
#import "PsiphonClientCommonLibraryHelpers.h"


@implementation AlertDialogs

+ (UIAlertController *)vpnPermissionDeniedAlert {
    // Alert the user that their permission is required in order to install the VPN configuration.
    UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:NSLocalizedStringWithDefaultValue(@"VPN_START_PERMISSION_REQUIRED_TITLE", nil, [NSBundle mainBundle], @"Permission required", @"Alert dialog title indicating to the user that Psiphon needs their permission")
                       message:NSLocalizedStringWithDefaultValue(@"VPN_START_PERMISSION_DENIED_MESSAGE", nil, [NSBundle mainBundle], @"Psiphon needs your permission to install a VPN profile in order to connect.\n\nPsiphon is committed to protecting the privacy of our users. You can review our privacy policy by tapping \"Privacy Policy\".", @"('Privacy Policy' should be the same translation as privacy policy button VPN_START_PRIVACY_POLICY_BUTTON), (Do not translate 'VPN profile'), (Do not translate 'Psiphon')")
                preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *privacyPolicyAction = [UIAlertAction
      actionWithTitle:NSLocalizedStringWithDefaultValue(@"VPN_START_PRIVACY_POLICY_BUTTON", nil, [NSBundle mainBundle], @"Privacy Policy", @"Button label taking user's to our Privacy Policy page")
                style:UIAlertActionStyleDefault
              handler:^(UIAlertAction *action) {
         NSString *urlString = NSLocalizedStringWithDefaultValue(@"PRIVACY_POLICY_URL", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"https://psiphon.ca/en/privacy.html", @"External link to the privacy policy page. Please update this with the correct language specific link (if available) e.g. https://psiphon.ca/fr/privacy.html for french.");
         [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString]
                                            options:@{}
                                  completionHandler:^(BOOL success) {
                                      // Do nothing.
                                  }];
     }];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedStringWithDefaultValue(@"VPN_START_PERMISSION_DISMISS_BUTTON", nil, [NSBundle mainBundle], @"Dismiss", @"Dismiss button title. Dismisses pop-up alert when the user clicks on the button")
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
      alertControllerWithTitle:NSLocalizedStringWithDefaultValue(@"ALERT_TITLE_OPERATION_FAILED", nil, [NSBundle mainBundle], @"Operation Failed", @"Alert dialog title.")
                       message:NSLocalizedStringWithDefaultValue(@"ALERT_BODY_OPERATION_FAILED", nil, [NSBundle mainBundle], @"Operation Failed, please try again.", @"Alert dialog body.")
                preferredStyle:UIAlertControllerStyleAlert];

    return alert;
}

@end