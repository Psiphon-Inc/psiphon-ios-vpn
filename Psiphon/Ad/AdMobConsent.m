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

#import "AdMobConsent.h"
#import "PsiFeedbackLogger.h"
#import "Logging.h"
#import "AppDelegate.h"
#import "PsiphonClientCommonLibraryHelpers.h"

PsiFeedbackLogType const AdMobConsentLogType = @"AdMobConsent";

@implementation AdMobConsent

+ (void)collectConsentForPublisherID:(NSString *)publisherID
               withCompletionHandler:(void (^_Nonnull)(NSError *_Nullable error, PACConsentStatus s))completion {

    // AdMob consent
    [PACConsentInformation.sharedInstance
      requestConsentInfoUpdateForPublisherIdentifiers:@[publisherID]
      completionHandler:^(NSError *error) {

          if (error) {
              // Logs the error. No ads should be loaded.
              [PsiFeedbackLogger errorWithType:AdMobConsentLogType
                                       message:@"consentInfoUpdateFailed"
                                        object:error];

              completion(error, PACConsentStatusUnknown);
              return;
          }

          LOG_DEBUG(@"ad mob consent info update succeeded");

          if (!PACConsentInformation.sharedInstance.requestLocationInEEAOrUnknown) {
              // User is not located in EEU. We can make ad requests to AdMob.
              // Per AdMob documentation below, we will keep the AdMob default which is to serve personalized ads.
              // https://developers.google.com/admob/ios/eu-consent#storing_publisher_managed_consent
              completion(nil, PACConsentStatusPersonalized);
              return;
          }

          // User is located in EEU, we now check consent status to check if consent has already
          // been provided.
          if (PACConsentInformation.sharedInstance.consentStatus == PACConsentStatusUnknown) {

              // Collect consent.
              NSURL *privacyURL = [NSURL URLWithString:NSLocalizedStringWithDefaultValue(@"PRIVACY_POLICY_URL", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"https://psiphon.ca/en/privacy.html", @"External link to the privacy policy page. Please update this with the correct language specific link (if available) e.g. https://psiphon.ca/fr/privacy.html for french.")];
              PACConsentForm *form = [[PACConsentForm alloc] initWithApplicationPrivacyPolicyURL:privacyURL];
              form.shouldOfferPersonalizedAds = YES;
              form.shouldOfferNonPersonalizedAds = YES;
              form.shouldOfferAdFree = NO;

              [form loadWithCompletionHandler:^(NSError *error) {
                  if (error) {
                      [PsiFeedbackLogger errorWithType:AdMobConsentLogType
                                               message:@"consentFormLoadFailed"
                                                object:error];

                      completion(error, PACConsentStatusUnknown);
                      return;
                  }

                  // Present the Google-rendered consent form.
                  [form presentFromViewController:[AppDelegate getTopMostViewController]
                    dismissCompletion:^(NSError *error, BOOL userPrefersAdFree) {

                        if (error) {
                            [PsiFeedbackLogger errorWithType:AdMobConsentLogType
                                                     message:@"consentFormPresentFailed"
                                                      object:error];

                            completion(error, PACConsentStatusUnknown);
                            return;
                        }

                        completion(nil, PACConsentInformation.sharedInstance.consentStatus);

                    }];
              }];

          } else {
              completion(nil, PACConsentInformation.sharedInstance.consentStatus);
          }
      }];
}

@end
