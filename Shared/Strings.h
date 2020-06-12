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
#import <StoreKit/StoreKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface StringUtils : NSObject

/**
 Converts `unit` to natural language (English only for now). `numUnits` determines if the output is pluralized or not.
 Examples: "Day", "Weeks", "mo.", "mos."
 */
+ (NSString *)stringForPeriodUnit:(SKProductPeriodUnit)unit
                 pluralGivenUnits:(NSUInteger)numUnits
                    andAbbreviate:(BOOL)abbreviate API_AVAILABLE(ios(11.2));

/**
 Converts `subscription` period to natural language (English onlyu for now). Examples: "1 Week", "Week", "2 mos.", ...
 @note 7 days is converted to 1 week.

 @param dropNumOfUnitsIfOne: drops prefixed number of units if its 1. E.g. 1 week -> "Week", but 2 weeks -> "2 Weeks".
 */
+ (NSString *)stringForSubscriptionPeriod:(SKProductSubscriptionPeriod *)subscription
                      dropNumOfUnitsIfOne:(BOOL)dropNumOfUnitsIfOne
                            andAbbreviate:(BOOL)abbreviate API_AVAILABLE(ios(11.2));

@end


@interface Strings : NSObject

#pragma mark - Generic Alert Strings

+ (NSString *)permissionRequiredAlertTitle;

+ (NSString *)operationFailedAlertTitle;

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

#pragma mark - VPN

+ (NSString *)vpnPermissionDeniedAlertMessage;

#pragma mark - Privacy Policy

+ (NSString *)privacyPolicyTitle;

+ (NSString *)privacyPolicyButtonTitle;

+ (NSString *)privacyPolicyHTMLText;

+ (NSString *)privacyPolicyDeclinedAlertBody;

#pragma mark - Subscription

+ (NSString *)activeSubscriptionBannerTitle;

+ (NSString *)inactiveSubscriptionBannerTitle;

+ (NSString *)inactiveSubscriptionBannerSubtitle;

+ (NSString *)manageYourSubscriptionButtonTitle;

+ (NSString *)iDontSeeMySubscriptionButtonTitle;

+ (NSString *)subscriptionScreenNoticeText;

+ (NSString *)subscriptionScreenCancelNoticeText;

+ (NSString *)productRequestFailedNoticeText;

#pragma mark - Extension

+ (NSString *)selectedRegionUnavailableAlertBody;

#if !(TARGET_IS_EXTENSION)
+ (NSString *)privacyPolicyURLString;
#endif

@end

NS_ASSUME_NONNULL_END
