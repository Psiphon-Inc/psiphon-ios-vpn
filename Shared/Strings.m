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


@implementation Strings

+ (NSString *)privacyPolicyTitle {
    return NSLocalizedStringWithDefaultValue(@"PrivacyTitle", nil, [NSBundle mainBundle], @"Privacy Policy", @"page title for the Privacy Policy page");
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
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhatdoespsiphondowithSubhead", nil, [NSBundle mainBundle], @"What does Psiphon do with your VPN data?", @"Sub-heading in the 'User VPN Data' section of the Privacy Policy page. The section describes what Psiphon does with the little bit of VPN data that it collects stats from."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhatdoespsiphondowithPara1", nil, [NSBundle mainBundle], @"Psiphon looks at your data only to the degree necessary to collect statistics about the usage of our system. We record the total bytes transferred for a user connection, as well as the bytes transferred for some specific domains. These statistics are discarded after 60 days.", @"Paragraph text in the 'What does Psiphon do with your VPN data?' subsection of the 'User VPN Data' section of the Privacy page."),
                     NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhatdoespsiphondowithPara2", nil, [NSBundle mainBundle], @"Psiphon does not inspect or record full URLs (only domain names), and does not further inspect your data. Psiphon does not modify your data as it passes through the VPN.", @"Paragraph text in the 'What does Psiphon do with your VPN data?' subsection of the 'User VPN Data' section of the Privacy page."),
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

@end
