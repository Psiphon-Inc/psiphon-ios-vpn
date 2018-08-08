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

#import "MoPubConsent.h"
#import "PsiFeedbackLogger.h"
#import <mopub-ios-sdk/MPConsentManager.h>
#import <mopub-ios-sdk/MoPub.h>
#import "AppDelegate.h"

PsiFeedbackLogType const MoPubConsentLogType = @"MoPubConsent";

@implementation MoPubConsent

+ (void)collectConsentWithCompletionHandler:(void (^)(NSError *_Nullable error))completion {

    if (![MoPub sharedInstance].shouldShowConsentDialog) {
        // MoPub consent is already given or is not needed.
        completion(nil);
        return;
    }

    [[MoPub sharedInstance] loadConsentDialogWithCompletion:^(NSError *error) {

        if (error) {
            [PsiFeedbackLogger errorWithType:MoPubConsentLogType
                                     message:@"consentDialogLoadFailed"
                                      object:error];

            completion(error);
            return;
        }

        // Present consent dialog
        [[MoPub sharedInstance]
          showConsentDialogFromViewController:[AppDelegate getTopMostViewController]
                                      didShow:nil
                                   didDismiss:^{
                                       // MoPub consent dialog was presented successfully and dismissed.
                                       completion(nil);
                                       return;
                                   }];

    }];

}

@end
