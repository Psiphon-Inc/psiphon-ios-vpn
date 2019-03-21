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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Strings : NSObject

#pragma mark - Generic Alert Strings

+ (NSString *)permissionRequiredAlertTitle;

+ (NSString *)operationFailedAlertTitle;

+ (NSString *)operationFailedAlertMessage;

#pragma mark - Generic Button Titles

+ (NSString *)acceptButtonTitle;

+ (NSString *)declineButtonTitle;

+ (NSString *)okButtonTitle;

+ (NSString *)dismissButtonTitle;

+ (NSString *)cancelButtonTitle;

+ (NSString *)doneButtonTitle;

#pragma mark - Subscriptions

+ (NSString *)manageSubscriptionButtonTitle;

+ (NSString *)subscribeButtonTitle;

#pragma mark - Misc

+ (NSString *)connectViaTitle;

+ (NSString *)selectLanguageTitle;

+ (NSString *)resetConsentButtonTitle;

#pragma mark - Onboarding

+ (NSString *)onboardingSelectLanguageButtonTitle;

+ (NSString *)onboardingBeyondBordersHeaderText;

+ (NSString *)onboardingBeyondBordersBodyText;

+ (NSString *)onboardingGettingStartedHeaderText;

+ (NSString *)onboardingGettingStartedBodyText;

+ (NSString *)vpnInstallGuideText;

+ (NSString *)nextPageButtonTitle;

#pragma mark - PsiCash

+ (NSString *)psiCashSpeedBoostMeterActiveTitle;

+ (NSString *)psiCashSpeedBoostMeterChargingTitle;

+ (NSString *)psiCashSpeedBoostMeterAvailableTitle;

+ (NSString *)psiCashSpeedBoostMeterBuyingTitle;

+ (NSString *)psiCashSpeedBoostMeterNoAuthTitle;

+ (NSString *)psiCashSpeedBoostMeterUserNotOnboardedTitle;

+ (NSString *)psiCashRewardedVideoButtonLoadingTitle;

+ (NSString *)psiCashRewardedVideoButtonRetryTitle;

#pragma mark - VPN

+ (NSString *)vpnPermissionDeniedAlertMessage;

#pragma mark - Privacy Policy

+ (NSString *)privacyPolicyTitle;

+ (NSString *)privacyPolicyButtonTitle;

+ (NSString *)privacyPolicyHTMLText;

+ (NSString *)privacyPolicyDeclinedAlertBody;

#pragma mark - Extension

+ (NSString *)selectedRegionUnavailableAlertBody;

#if !(TARGET_IS_EXTENSION)
+ (NSString *)privacyPolicyURLString;
#endif

@end

NS_ASSUME_NONNULL_END
