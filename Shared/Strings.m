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

#import "Strings.h"

#if !(TARGET_IS_EXTENSION)
#import "PsiphonClientCommonLibraryHelpers.h"
#endif


@implementation Strings

+ (NSString *)permissionRequiredAlertTitle {
    return NSLocalizedStringWithDefaultValue(@"PERMISSION_REQUIRED_ALERT__TITLE", nil, [NSBundle mainBundle], @"Permission required", @"Alert dialog title indicating to the user that Psiphon needs their permission");
}

+ (NSString *)operationFailedAlertTitle {
    return NSLocalizedStringWithDefaultValue(@"ALERT_TITLE_OPERATION_FAILED", nil, [NSBundle mainBundle], @"Operation Failed", @"Alert dialog title.");
}

+ (NSString *)operationFailedAlertMessage {
    return NSLocalizedStringWithDefaultValue(@"ALERT_BODY_OPERATION_FAILED", nil, [NSBundle mainBundle], @"Operation failed, please try again.", @"Alert dialog body.");
}

+ (NSString *)acceptButtonTitle {
    return  NSLocalizedStringWithDefaultValue(@"ACCEPT_BUTTON_TITLE", nil, [NSBundle mainBundle], @"Accept", @"Accept button title");
}

+ (NSString *)declineButtonTitle {
    return  NSLocalizedStringWithDefaultValue(@"DECLINE_BUTTON_TITLE", nil, [NSBundle mainBundle], @"Decline", @"Decline button title");
}

+ (NSString *)okButtonTitle {
    return NSLocalizedStringWithDefaultValue(@"OK_BUTTON", nil, [NSBundle mainBundle], @"OK", @"Alert OK Button");
}

+ (NSString *)dismissButtonTitle {
    return NSLocalizedStringWithDefaultValue(@"DISMISS_BUTTON_TITLE", nil, [NSBundle mainBundle], @"Dismiss", @"Dismiss button title. Dismisses pop-up alert when the user clicks on the button");
}

+ (NSString *)cancelButtonTitle {
    return  NSLocalizedStringWithDefaultValue(@"CANCEL_BUTTON_TITLE", nil, [NSBundle mainBundle], @"Cancel", @"Title for a button that cancels an action. This should be generic enough to make sense whenever a cancel button is used.");
}

+ (NSString *)doneButtonTitle {
    return NSLocalizedStringWithDefaultValue(@"DONE_BUTTON_TITLE", nil, [NSBundle mainBundle], @"Done", @"Title of the button that dismisses a screen or a dialog");
}

+ (NSString *)manageSubscriptionButtonTitle {
    return NSLocalizedStringWithDefaultValue(@"SUBSCRIPTIONS_MANAGE_SUBSCRIPTION_BUTTON", nil, [NSBundle mainBundle], @"Manage", @"Label on a button which, when pressed, opens a screen where the user can manage their currently active subscription.");
}

+ (NSString *)subscribeButtonTitle {
    return NSLocalizedStringWithDefaultValue(@"SUBSCRIPTIONS_SUBSCRIBE_BUTTON", nil, [NSBundle mainBundle], @"Subscribe", @"Label on a button which, when pressed, opens a screen where the user can choose from multiple subscription plans.");
}

+ (NSString *)connectViaTitle {
    return  NSLocalizedStringWithDefaultValue(@"CONNECT_VIA", nil, [NSBundle mainBundle], @"CONNECT VIA", @"Title for screen that allows user to select their desired server region. Use all capital letters in the translation only if it makes sense.");
}

+ (NSString *)selectLanguageTitle {
    return  NSLocalizedStringWithDefaultValue(@"SELECT_LANG", nil, [NSBundle mainBundle], @"SELECT LANGUAGE", @"Title for screen that allows user to select language. Use all capital letters in the translation only if it makes sense.");
}

+ (NSString *)resetConsentButtonTitle {
    return  NSLocalizedStringWithDefaultValue(@"RESET_IDENTIFIER_BUTTON_TITLE", nil, [NSBundle mainBundle], @"Reset Consent", @"Title for a confirmation button that resets a user's previous consent.");
}

+ (NSString *)onboardingSelectLanguageButtonTitle {
    return  NSLocalizedStringWithDefaultValue(@"SELECT_LANG_BUTTON_TITLE", nil, [NSBundle mainBundle], @"Select Language", @"Select language button title.");
}

+ (NSString *)onboardingBeyondBordersHeaderText {
    return  NSLocalizedStringWithDefaultValue(@"ONBOARDING_BEYOND_BORDERS_HEADER", nil, [NSBundle mainBundle], @"Beyond Borders", @"Beyond Borders title");
}

+ (NSString *)onboardingBeyondBordersBodyText {
    return  NSLocalizedStringWithDefaultValue(@"ONBOARDING_BEYOND_BORDERS_BODY", nil, [NSBundle mainBundle], @"Censored by your country, corporation, or campus? Psiphon is uniquely suited to help you get to the content you want, whenever and wherever you want it.", @"Onboarding screen text. (Do not translate 'Psiphon').");
}

+ (NSString *)onboardingGettingStartedHeaderText {
    return  NSLocalizedStringWithDefaultValue(@"ONBOARDING_GETTING_STARTED_HEADER", nil, [NSBundle mainBundle], @"Getting Started", @"Onboarding header");
}

+ (NSString *)onboardingGettingStartedBodyText {
    return  NSLocalizedStringWithDefaultValue(@"ONBOARDING_GETTING_STARTED_BODY", nil, [NSBundle mainBundle], @"Psiphon uses VPN technology to provide you with uncensored access to internet content. You’ll need to allow Psiphon to add VPN configurations to your phone in order to connect with a safe path to the internet.", @"Onboarding screen 'getting started' body.");
}

+ (NSString *)vpnInstallGuideText {
    return  NSLocalizedStringWithDefaultValue(@"ONBARDING_VPN_INSTALL_GUIDE_TEXT", nil, [NSBundle mainBundle], @"You’ll need to allow Psiphon to add VPN configurations in order to connect.", @"Onboarding text for install VPN configuration. (Do not translate 'Psiphon').");
}

+ (NSString *)nextPageButtonTitle {
    return  NSLocalizedStringWithDefaultValue(@"NEXT_PAGE_BUTTON_TITLE", nil, [NSBundle mainBundle], @"Next", @"Button title that takes user to the next page");
}

+ (NSString *)psiCashSpeedBoostMeterActiveTitle {
    return NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_ACTIVE_TEXT", nil, [NSBundle mainBundle], @"Speed Boost Active", @"Text which appears in the Speed Boost meter when the user has activated Speed Boost. Please keep this text concise as the width of the text box is restricted in size. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.");
}

+ (NSString *)psiCashSpeedBoostMeterChargingTitle {
    return NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_CHARGING_TEXT", nil, [NSBundle mainBundle], @"Speed Boost Charging", @"Text which appears in the Speed Boost meter when the user has not yet earned enough PsiCash to Speed Boost. This text will be accompanied with a percentage indicating to the user how close they are to earning enough PsiCash to buy a minimum amount of Speed Boost. Please keep this text concise as the width of the text box is restricted in size. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.");
}

+ (NSString *)psiCashSpeedBoostMeterAvailableTitle {
    return NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_AVAILABLE_TEXT", nil, [NSBundle mainBundle], @"Speed Boost Available", @"Text which appears in the Speed Boost meter when the user has earned enough PsiCash to buy Speed Boost. Please keep this text concise as the width of the text box is restricted in size. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.");
}

+ (NSString *)psiCashSpeedBoostMeterBuyingTitle {
    return NSLocalizedStringWithDefaultValue(@"PSICASH_BUYING_SPEED_BOOST_TEXT", nil, [NSBundle mainBundle], @"Buying Speed Boost...", @"Text which appears in the Speed Boost meter when the user's buy request for Speed Boost is being processed. Please keep this text concise as the width of the text box is restricted in size.");
}

+ (NSString *)psiCashSpeedBoostMeterNoAuthTitle {
    return NSLocalizedStringWithDefaultValue(@"PSICASH_SPEED_BOOST_NOAUTH_TEXT", nil, [NSBundle mainBundle], @"Earn PsiCash to buy Speed Boost", @"Text which appears in the Speed Boost meter when the user has not earned any PsiCash yet. Please keep this text concise as the width of the text box is restricted in size. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed. Note: 'PsiCash' should not be translated or transliterated.");
}

+ (NSString *)vpnPermissionDeniedAlertMessage {
    return NSLocalizedStringWithDefaultValue(@"VPN_START_PERMISSION_DENIED_MESSAGE", nil, [NSBundle mainBundle], @"Psiphon needs your permission to install a VPN profile in order to connect.\n\nPsiphon is committed to protecting the privacy of our users. You can review our privacy policy by tapping \"Privacy Policy\".", @"('Privacy Policy' should be the same translation as privacy policy button VPN_START_PRIVACY_POLICY_BUTTON), (Do not translate 'VPN profile'), (Do not translate 'Psiphon')");
}

+ (NSString *)privacyPolicyTitle {
    return NSLocalizedStringWithDefaultValue(@"PrivacyTitle", nil, [NSBundle mainBundle], @"Privacy Policy", @"page title for the Privacy Policy page");
}

+ (NSString *)privacyPolicyButtonTitle {
    return NSLocalizedStringWithDefaultValue(@"VPN_START_PRIVACY_POLICY_BUTTON", nil, [NSBundle mainBundle], @"Privacy Policy", @"Button label taking user's to our Privacy Policy page");
}

+ (NSString *)privacyPolicyHTMLText {
    NSString *format = @"\
        <h2>%1$@</h2>\
        <p>%2$@</p>\
        <br>\
        <h2>%3$@</h2>\
        <p>%4$@</p>\
        <p>%5$@</p>\
        <p>%6$@</p>\
        <br>\
        <h2>%7$@</h2>\
        <p>%8$@</p>\
        <ul>\
            <li>%9$@</li>\
            <li>%10$@</li>\
            <li>%11$@</li>\
            <li>%12$@</li>\
        </ul>\
        <br>\
        <h2>%13$@</h2>\
        <p>%14$@</p>\
        <p>%15$@</p>\
        <p>%16$@</p>\
    ";

    return [NSString stringWithFormat:format,
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhycareSubhead", nil, [NSBundle mainBundle], @"Why should you care?", @"Sub-heading in the 'User VPN Data' section of the Privacy Policy page. The section describes why it's important for users to consider what a VPN does with their traffic data."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhycarePara1", nil, [NSBundle mainBundle], @"When using a VPN or proxy you should be concerned about what the provider can see in your data, collect from it, and do to it. For some web and email connections, it is theoretically possible for a VPN to see, collect, and modify the contents.", @"Paragraph text in the 'Why should you care?' subsection of the 'User VPN Data' section of the Privacy page."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhatdoespsiphondowithSubhead", nil, [NSBundle mainBundle], @"What does Psiphon do with your VPN data?", @"Sub-heading in the 'User VPN Data' section of the Privacy Policy page. The section describes what Psiphon does with the little bit of VPN data that it collects stats from."), NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhatdoespsiphondowithPara1", nil, [NSBundle mainBundle], @"Psiphon looks at your data only to the degree necessary to collect statistics about the usage of our system. We record the total bytes transferred for a user connection, as well as the bytes transferred for some specific domains. These statistics are discarded after 60 days.", @"Paragraph text in the 'What does Psiphon do with your VPN data?' subsection of the 'User VPN Data' section of the Privacy page."), NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhatdoespsiphondowithPara2", nil, [NSBundle mainBundle], @"Psiphon does not inspect or record full URLs (only domain names), and does not further inspect your data. Psiphon does not modify your data as it passes through the VPN.", @"Paragraph text in the 'What does Psiphon do with your VPN data?' subsection of the 'User VPN Data' section of the Privacy page."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhatdoespsiphondowithPara3", nil, [NSBundle mainBundle], @"Even this coarse data would be difficult to link back to you, since we immediately convert your IP address to geographical info and then discard the IP. Nor is any other identifying information stored.", @"Paragraph text in the 'What does Psiphon do with your VPN data?' subsection of the 'User VPN Data' section of the Privacy page."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhydoespsiphonneedSubhead", nil, [NSBundle mainBundle], @"Why does Psiphon need these statistics?", @"Sub-heading in the 'User VPN Data' section of the Privacy Policy page. The section describes why Psiphon needs VPN data stats."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhydoespsiphonneedPara1ListStart", nil, [NSBundle mainBundle], @"This data is used by us to determine how our network is being used. This allows us to do things like:", @"Paragraph text in the 'Why does Psiphon need these statistics?' subsection of the 'User VPN Data' section of the Privacy page. This paragraph serves as preamble for a detailed list, which is why it ends with a colon."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhydoespsiphonneedPara1Item1", nil, [NSBundle mainBundle], @"Estimate future costs: The huge amount of user data we transfer each month is a major factor in our costs. It is vital for us to see and understand usage fluctuations.", @"Bullet list text under 'Why does Psiphon need these statistics?' subsection of the 'User VPN Data' section of the Privacy page."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhydoespsiphonneedPara1Item2", nil, [NSBundle mainBundle], @"Optimize for traffic types: Video streaming has different network requirements than web browsing does, which is different than chat, which is different than voice, and so on. Statistics about the number of bytes transferred for some major media providers helps us to understand how to provide the best experience to our users.", @"Bullet list text under 'Why does Psiphon need these statistics?' subsection of the 'User VPN Data' section of the Privacy page."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhydoespsiphonneedPara1Item3", nil, [NSBundle mainBundle], @"Determine the nature of major censorship events: Sites and services often get blocked suddenly and without warning, which can lead to huge variations in regional usage of Psiphon. For example, we had up to 20x surges in usage within a day when <a href=\"https://blog-en.psiphon.ca/2016/07/psiphon-usage-surges-as-brazil-blocks.html\" target=\"_blank\">Brazil blocked WhatsApp</a> or <a href=\"https://blog-en.psiphon.ca/2016/11/social-media-and-internet-ban-in-turkey.html\" target=\"_blank\">Turkey blocked social media</a>.", @"Bullet list text under 'Why does Psiphon need these statistics?' subsection of the 'User VPN Data' section of the Privacy page. If available in your language, the blog post URLs should be updated to the localized post."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhydoespsiphonneedPara1Item4", nil, [NSBundle mainBundle], @"Understand who we need to help: Some sites and services will never get blocked anywhere, some will always be blocked in certain countries, and some will occasionally be blocked in some countries. To make sure that our users are able to communicate and learn freely, we need to understand these patterns, see who is affected, and work with partners to make sure their services work best with Psiphon.", @"Bullet list text under 'Why does Psiphon need these statistics?' subsection of the 'User VPN Data' section of the Privacy page. (English is using 'who' instead of 'whom' to reflect common idiom.)"),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhopsiphonshareswithSubhead", nil, [NSBundle mainBundle], @"Who does Psiphon share these statistics with?", @"Sub-heading in the 'User VPN Data' section of the Privacy Policy page. The section describes who Psiphon shares VPN data stats. The answer will be organizations and not specific people, in case that makes a difference in your language."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhopsiphonshareswithPara1", nil, [NSBundle mainBundle], @"When sharing with third parties, Psiphon only ever provides coarse, aggregate domain-bytes statistics. We never share per-session information or any other possibly-identifying information.", @"Paragraph text in the 'Who does Psiphon share these statistics with?' subsection of the 'User VPN Data' section of the Privacy page."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhopsiphonshareswithPara2", nil, [NSBundle mainBundle], @"This sharing is typically done with services or organizations we collaborate with — as <a href=\"http://www.dw.com/en/psiphon-helps-dodge-the-online-trackers/a-16765092\" target=\"_blank\">we did with DW</a> a few years ago. These statistics help us and them answer questions like, “how many bytes were transferred through Psiphon for DW.com to all users in Iran in April?”", @"Paragraph text in the 'Who does Psiphon share these statistics with?' subsection of the 'User VPN Data' section of the Privacy page."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhopsiphonshareswithPara3", nil, [NSBundle mainBundle], @"Again, we specifically do not give detailed or potentially user-identifying information to partners or any other third parties.", @"Paragraph text in the 'Who does Psiphon share these statistics with?' subsection of the 'User VPN Data' section of the Privacy page.")
    ];
}

+ (NSString *)privacyPolicyDeclinedAlertBody {
    return  NSLocalizedStringWithDefaultValue(@"PRIVACY_POLICY_DECLINED_ALERT_BODY", nil, [NSBundle mainBundle], @"You must accept our Privacy Policy before continuing to use Psiphon.", @"Alert message when the user declined privacy policy. They will not be able ot use the app until the user accepts the privacy policy (Do not translate 'Psiphon')");
}

+ (NSString *)selectedRegionUnavailableAlertBody {
    return NSLocalizedStringWithDefaultValue(@"VPN_START_FAIL_REGION_INVALID_MESSAGE_2", nil, [NSBundle mainBundle], @"The region you selected is no longer available. You have automatically been switched to \"Fastest Country\".\n\n You can also select a new region from the Psiphon app.", @"Alert dialog message informing the user that an error occurred while starting Psiphon because they selected an egress region that is no longer available (Do not translate 'Psiphon'). The user has been automatically switched to to 'Fastest Country', but they can also open the Psiphon app to choose another country. Note: the backslash before each quotation mark should be left as is for formatting.");
}

#if !(TARGET_IS_EXTENSION)
+ (NSString *)privacyPolicyURLString {
    return NSLocalizedStringWithDefaultValue(@"PRIVACY_POLICY_URL", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"https://psiphon.ca/en/privacy.html", @"External link to the privacy policy page. Please update this with the correct language specific link (if available) e.g. https://psiphon.ca/fr/privacy.html for french.");
}
#endif

@end
