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

#import "AppDelegate.h"
#import "UIAlertController+Delegate.h"

@implementation UIAlertController (Delegate)

+ (void)presentSimpleAlertWithTitle:(NSString *_Nonnull)title message:(NSString *_Nonnull)message preferredStyle:(UIAlertControllerStyle)preferredStyle okHandler:(void (^ _Nullable)(UIAlertAction *action))okHandler {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:preferredStyle];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedStringWithDefaultValue(@"OK_BUTTON", nil, [NSBundle mainBundle], @"OK", @"Alert OK Button") style:UIAlertActionStyleDefault handler:okHandler];
    [ac addAction:okAction];
    [ac presentFromTopController];
}

/**
 * Presents this instance from application's key window top most view controller.
 */
- (void)presentFromTopController {
    [[AppDelegate getTopMostViewController] presentViewController:self animated:TRUE completion:nil];
}

- (void)addDismissAction:(void (^)(UIAlertAction *action))handler {
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedStringWithDefaultValue(@"VPN_START_PERMISSION_DISMISS_BUTTON", nil, [NSBundle mainBundle], @"Dismiss", @"Dismiss button title. Dismisses pop-up alert when the user clicks on the button")
                                                            style:UIAlertActionStyleCancel
                                                          handler:handler];
    [self addAction:dismissAction];
}

@end
