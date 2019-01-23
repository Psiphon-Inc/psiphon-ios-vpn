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

#import "PrivacyPolicyViewController.h"
#import "UIColor+Additions.h"
#import "NSError+Convenience.h"
#import "PsiFeedbackLogger.h"
#import "SwoopView.h"

NSNotificationName const PrivacyPolicyDismissedNotification = @"PrivacyPolicyDismissedNotification";
NotificationUserInfoKey const PrivacyPolicyAcceptedNotificationBoolKey =
    @"PrivacyPolicyAcceptedNotificationBoolKey";

NSErrorDomain _Nonnull const PrivacyPolicyErrorDomain = @"PrivacyPolicyErrorDomain";

typedef NS_ERROR_ENUM(PrivacyPolicyErrorDomain, PrivacyPolicyLinkGenerationErrorCode) {

    PrivacyPolicyLinkGenerationInvalidErrorPointer          = 1 << 0,
    PrivacyPolicyLinkGenerationFailedToFindHref             = 1 << 1,
    PrivacyPolicyLinkGenerationFailedToGenerateURL          = 1 << 2,
    PrivacyPolicyLinkGenerationFailedToFindCloseTag         = 1 << 3,
    PrivacyPolicyLinkGenerationEncounteredInvalidRange      = 1 << 4,

};

@interface SectionView : UIView

@property (nonatomic) UILabel *header;
@property (nonatomic) UILabel *subheading;
@property (nonatomic) UITextView *body;
@property (nonatomic, weak) UIView *anchorView;

@property (nonatomic) NSNumber *bottomAnchorConstant;
@property (nonatomic) NSArray<NSNumber *> *subviewsTopAnchorConstants;

- (instancetype)initWithSubheading;
- (void)addViewsAndApplyConstraints;

@end

@implementation SectionView

+ (UILabel *)createLabel {
    UILabel *l = [[UILabel alloc] init];
    l.adjustsFontSizeToFitWidth = TRUE;
    l.numberOfLines = 0;  // Breaks text into as many lines as needed.
    return l;
}

+ (UITextView *)createTextView {
    UITextView *t = [[UITextView alloc] init];
    t.scrollEnabled = NO;
    t.editable = NO;
    return t;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _header = [SectionView createLabel];
        _header.font = [UIFont systemFontOfSize:26.0f weight:UIFontWeightMedium];

        _body= [SectionView createTextView];
        _body.alpha = 0.7;
        _body.font = [UIFont systemFontOfSize:18.0f weight:UIFontWeightRegular];

        _bottomAnchorConstant = @0.0;
        _subviewsTopAnchorConstants = @[@0.0, @16.0];
    }
    return self;
}

- (instancetype)initWithSubheading {
    self = [self init];
    if (self) {
        _subheading = [SectionView createLabel];
        _subheading.font = [UIFont systemFontOfSize:26.0f weight:UIFontWeightMedium];
        _subviewsTopAnchorConstants = @[@0.0, @16.0, @8.0];
    }
    return self;
}

- (void)addViewsAndApplyConstraints {

    // Add subviews
    [self addSubview:self.header];
    if (self.subheading.text) {
        [self addSubview:self.subheading];
    } else {
        self.subheading = nil;
    }
    [self addSubview:self.body];

    // Add subviews
    self.translatesAutoresizingMaskIntoConstraints = FALSE;
    self.preservesSuperviewLayoutMargins = TRUE;
    [self.bottomAnchor constraintEqualToAnchor:self.subviews.lastObject.bottomAnchor constant:self.bottomAnchorConstant.floatValue].active = TRUE;

    // constraints for all subviews
    [self.subviews enumerateObjectsUsingBlock:^(__kindof UIView *v, NSUInteger idx, BOOL *stop) {
        v.translatesAutoresizingMaskIntoConstraints = FALSE;
        v.preservesSuperviewLayoutMargins = TRUE;
        [v.widthAnchor constraintEqualToAnchor:self.layoutMarginsGuide.widthAnchor].active = TRUE;
        [v.centerXAnchor constraintEqualToAnchor:self.layoutMarginsGuide.centerXAnchor].active = TRUE;

        // Apply top anchor constraint except to the first object
        if (idx == 0) {
            [v.topAnchor constraintEqualToAnchor:self.layoutMarginsGuide.topAnchor
                                        constant:self.subviewsTopAnchorConstants[idx].floatValue].active = TRUE;
        } else {
            [v.topAnchor constraintEqualToAnchor:self.subviews[idx - 1].bottomAnchor
                                        constant:self.subviewsTopAnchorConstants[idx].floatValue].active = TRUE;
        }

    }];
}

@end

#pragma mark - view controller

@implementation PrivacyPolicyViewController {
    UIScrollView *_scrollView;
    UIStackView *_stackView;
}

// Force portrait orientation
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.whiteColor;

    UIEdgeInsets safeAreaInsets;
    if (@available(iOS 11.0, *)) {
        safeAreaInsets = UIApplication.sharedApplication.keyWindow.safeAreaInsets;  // Note that self.view.safeAreaInsets is 0 at viewDidLoad
    } else {
        safeAreaInsets = UIApplication.sharedApplication.keyWindow.layoutMargins;
    }

    // Get started with Psiphon button
    UIView *getStartedContainer = [[UIView alloc] init];
    {
        getStartedContainer.backgroundColor = UIColor.paleBlueColor;
        [self.view addSubview:getStartedContainer];

        // getStartedContainer constraints
        getStartedContainer.translatesAutoresizingMaskIntoConstraints = FALSE;
        getStartedContainer.preservesSuperviewLayoutMargins = TRUE;
        [getStartedContainer.widthAnchor constraintEqualToAnchor:self.view.widthAnchor].active = TRUE;
        [getStartedContainer.centerXAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.centerXAnchor].active = TRUE;
        [getStartedContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = TRUE;
        [getStartedContainer.heightAnchor constraintEqualToConstant:(CGFloat) (62.0 + safeAreaInsets.bottom)].active = TRUE;

        UIButton *getStartedButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        getStartedButton.backgroundColor = UIColor.clearBlueColor;
        getStartedButton.layer.cornerRadius = 5.0;
        getStartedButton.layer.masksToBounds = FALSE;
        getStartedButton.layer.shadowColor = [UIColor.clearBlue50Color CGColor];
        getStartedButton.layer.shadowRadius = 6;
        getStartedButton.layer.shadowOpacity = 1;
        getStartedButton.layer.shadowOffset = CGSizeMake(1.0, 1.0);
        getStartedButton.titleEdgeInsets = UIEdgeInsetsMake(0.0, 24.0, 0.0, 24.0);

        [getStartedButton setTitle:NSLocalizedStringWithDefaultValue(@"PrivacyPolicyGetStartedButtonTitle", nil, [NSBundle mainBundle], @"Get started with Psiphon", @"Button label at the end of privacy policy screen, indication that when clicked user can start using Psiphon")
                          forState:UIControlStateNormal];
        [getStartedButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [getStartedButton addTarget:self action:@selector(onGetStartedTap) forControlEvents:UIControlEventTouchUpInside];
        [getStartedContainer addSubview:getStartedButton];

        // Get started button constraints
        getStartedButton.translatesAutoresizingMaskIntoConstraints = FALSE;
        getStartedButton.preservesSuperviewLayoutMargins = TRUE;
        [getStartedButton.widthAnchor constraintEqualToConstant:223.0].active = TRUE;
        [getStartedButton.centerXAnchor constraintEqualToAnchor:getStartedContainer.centerXAnchor].active = TRUE;
        [getStartedButton.topAnchor constraintEqualToAnchor:getStartedContainer.topAnchor constant:16.0].active = TRUE;
//        [getStartedButton.centerYAnchor constraintEqualToAnchor:getStartedContainer.centerYAnchor].active = TRUE;
        [getStartedButton.heightAnchor constraintEqualToConstant:42.0].active = TRUE;
    }

    // scrollView
    _scrollView = [[UIScrollView alloc] init];
    [self.view addSubview:_scrollView];

    // scrollView constraints
    _scrollView.translatesAutoresizingMaskIntoConstraints = FALSE;
    [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = TRUE;
    [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = TRUE;
    if (@available(iOS 11.0, *)) {
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor].active = TRUE;
    } else {
        [_scrollView.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor].active = TRUE;
    }
    [_scrollView.bottomAnchor constraintEqualToAnchor:getStartedContainer.topAnchor].active = TRUE;

    // stackView
    _stackView = [[UIStackView alloc] init];
    _stackView.axis = UILayoutConstraintAxisVertical;
    _stackView.spacing = UIStackViewDistributionEqualSpacing;
    _stackView.alignment = UIStackViewAlignmentFill;
    _stackView.spacing = 40.0;
    _stackView.distribution = UIStackViewDistributionFill;
    [_scrollView addSubview:_stackView];

    // stackView constraints
    _stackView.translatesAutoresizingMaskIntoConstraints = FALSE;
    [_stackView.centerXAnchor constraintEqualToAnchor:_scrollView.centerXAnchor].active = TRUE;
    [_stackView.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor].active = TRUE;
    [_stackView.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor].active = TRUE;
    [_stackView.topAnchor constraintEqualToAnchor:_scrollView.topAnchor].active = TRUE;
    [_stackView.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor].active = TRUE;
    
    // Margin to be applied to the texts
    _stackView.layoutMargins = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16);

    // Adds all StackView elements to the _stackView.
    [self addStackedViews:_stackView safeAreaInsets:safeAreaInsets];


    // Cancel button
    {
        UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        cancelButton.titleEdgeInsets = UIEdgeInsetsMake(0.0, 5.0, 0.0, 5.0);
        [cancelButton sizeToFit];
        cancelButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.9];
        cancelButton.layer.masksToBounds = FALSE;
        cancelButton.layer.cornerRadius = 10.0;
        cancelButton.layer.shadowColor = [UIColor.darkGrayColor CGColor];
        cancelButton.layer.shadowRadius = 4;
        cancelButton.layer.shadowOpacity = 0.3;
        cancelButton.layer.shadowOffset = CGSizeMake(1.0, 1.0);
        [cancelButton setTitle:NSLocalizedStringWithDefaultValue(@"PRIVACY_POLICY_CANCEL_BUTTON", nil, [NSBundle mainBundle], @"Cancel", @"Cancel button title.")
                      forState:UIControlStateNormal];
        [cancelButton setTitleColor:UIColor.darkGrayColor forState:UIControlStateNormal];
        [cancelButton addTarget:self action:@selector(onCancelTap) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:cancelButton];

        // Close button constraints
        cancelButton.translatesAutoresizingMaskIntoConstraints = FALSE;
        [cancelButton.widthAnchor constraintEqualToConstant:60.0].active = TRUE;
        if (@available(iOS 11.0, *)) {
            [cancelButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10].active = TRUE;
        } else {
            [cancelButton.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor constant:10].active = TRUE;
        }
        [cancelButton.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor constant:0.0].active = TRUE;
    }
}

- (void)addStackedViews:(UIStackView *)stackView safeAreaInsets:(UIEdgeInsets)safeAreaInsets{
    NSError *e;
    
    UIView *sec1Container = [[UIView alloc] init];
    sec1Container.backgroundColor = UIColor.paleBlueColor;
    sec1Container.translatesAutoresizingMaskIntoConstraints = FALSE;
    sec1Container.layoutMargins = UIEdgeInsetsMake(0.0, safeAreaInsets.left, 0.0, safeAreaInsets.right);
    [stackView addArrangedSubview:sec1Container];
    
    // Section 1
    SectionView *sec1 = [[SectionView alloc] initWithSubheading];
    sec1.anchorView = sec1Container;
    sec1.bottomAnchorConstant = @40.0;
    sec1.subviewsTopAnchorConstants = @[@0, @40.0, @16.0, @8.0];
    sec1.header.font = [UIFont systemFontOfSize:32.0f weight:UIFontWeightMedium];
    sec1.header.text = NSLocalizedStringWithDefaultValue(@"PrivacyTitle", nil, [NSBundle mainBundle], @"Privacy Policy", @"page title for the Privacy Policy page");
    sec1.subheading.text = NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhycareSubhead", nil, [NSBundle mainBundle], @"Why should you care?", @"Sub-heading in the 'User VPN Data' section of the Privacy Policy page. The section describes why it's important for users to consider what a VPN does with their traffic data.");
    sec1.body.text = NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhycarePara1", nil, [NSBundle mainBundle], @"When using a VPN or proxy you should be concerned about what the provider can see in your data, collect from it, and do to it. For some web and email connections, it is theoretically possible for a VPN to see, collect, and modify the contents.", @"Paragraph text in the 'Why should you care?' subsection of the 'User VPN Data' section of the Privacy page.");
    sec1.body.backgroundColor = UIColor.paleBlueColor;

    
    // Adds PrivacyPolicyWelcome image to section 1
    UIImageView *welcomeImageView = [[UIImageView alloc] init];
    welcomeImageView.translatesAutoresizingMaskIntoConstraints = FALSE;
    welcomeImageView.image = [UIImage imageNamed:@"PrivacyPolicyWelcome"];
    welcomeImageView.contentMode = UIViewContentModeScaleAspectFit;
    [sec1 insertSubview:welcomeImageView atIndex:0];
    [sec1Container addSubview:sec1];
    [sec1 addViewsAndApplyConstraints];
    
    [sec1.leadingAnchor constraintEqualToAnchor:sec1Container.layoutMarginsGuide.leadingAnchor].active = TRUE;
    [sec1.trailingAnchor constraintEqualToAnchor:sec1Container.layoutMarginsGuide.trailingAnchor].active = TRUE;
    
    [sec1Container.widthAnchor constraintEqualToAnchor:stackView.widthAnchor].active = TRUE;
    [sec1Container.topAnchor constraintEqualToAnchor:sec1.topAnchor constant:-safeAreaInsets.top].active = TRUE;
    [sec1Container.bottomAnchor constraintEqualToAnchor:sec1.bottomAnchor].active = TRUE;

    // Section 2
    NSArray *sec2BodyParagraphs = @[
      NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhatdoespsiphondowithPara1", nil, [NSBundle mainBundle], @"Psiphon looks at your data only to the degree necessary to collect statistics about the usage of our system. We record the total bytes transferred for a user connection, as well as the bytes transferred for some specific domains. These statistics are discarded after 60 days.", @"Paragraph text in the 'What does Psiphon do with your VPN data?' subsection of the 'User VPN Data' section of the Privacy page."),
      NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhatdoespsiphondowithPara2", nil, [NSBundle mainBundle], @"Psiphon does not inspect or record full URLs (only domain names), and does not further inspect your data. Psiphon does not modify your data as it passes through the VPN.", @"Paragraph text in the 'What does Psiphon do with your VPN data?' subsection of the 'User VPN Data' section of the Privacy page."),
      NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhatdoespsiphondowithPara3", nil, [NSBundle mainBundle], @"Even this coarse data would be difficult to link back to you, since we immediately convert your IP address to geographical info and then discard the IP. Nor is any other identifying information stored.", @"Paragraph text in the 'What does Psiphon do with your VPN data?' subsection of the 'User VPN Data' section of the Privacy page.")
    ];

    SectionView *sec2 = [[SectionView alloc] init];
    sec2.anchorView = stackView;
    sec2.header.text = NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhatdoespsiphondowithSubhead", nil, [NSBundle mainBundle], @"What does Psiphon do with your VPN data?", @"Sub-heading in the 'User VPN Data' section of the Privacy Policy page. The section describes what Psiphon does with the little bit of VPN data that it collects stats from.");
    sec2.body.text = [sec2BodyParagraphs componentsJoinedByString:@"\n\n"];
    [stackView addArrangedSubview:sec2];
    [sec2 addViewsAndApplyConstraints];

    // Section 3
    NSMutableArray *sec3BodyItems = [NSMutableArray arrayWithArray:@[
      NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhydoespsiphonneedPara1Item1", nil, [NSBundle mainBundle], @"Estimate future costs: The huge amount of user data we transfer each month is a major factor in our costs. It is vital for us to see and understand usage fluctuations.", @"Bullet list text under 'Why does Psiphon need these statistics?' subsection of the 'User VPN Data' section of the Privacy page."),
      NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhydoespsiphonneedPara1Item2", nil, [NSBundle mainBundle], @"Optimize for traffic types: Video streaming has different network requirements than web browsing does, which is different than chat, which is different than voice, and so on. Statistics about the number of bytes transferred for some major media providers helps us to understand how to provide the best experience to our users.", @"Bullet list text under 'Why does Psiphon need these statistics?' subsection of the 'User VPN Data' section of the Privacy page."),
      NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhydoespsiphonneedPara1Item3", nil, [NSBundle mainBundle], @"Determine the nature of major censorship events: Sites and services often get blocked suddenly and without warning, which can lead to huge variations in regional usage of Psiphon. For example, we had up to 20x surges in usage within a day when <a href=\"https://blog-en.psiphon.ca/2016/07/psiphon-usage-surges-as-brazil-blocks.html\" target=\"_blank\">Brazil blocked WhatsApp</a> or <a href=\"https://blog-en.psiphon.ca/2016/11/social-media-and-internet-ban-in-turkey.html\" target=\"_blank\">Turkey blocked social media</a>.", @"Bullet list text under 'Why does Psiphon need these statistics?' subsection of the 'User VPN Data' section of the Privacy page. If available in your language, the blog post URLs should be updated to the localized post."),
      NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhydoespsiphonneedPara1Item4", nil, [NSBundle mainBundle], @"Understand who we need to help: Some sites and services will never get blocked anywhere, some will always be blocked in certain countries, and some will occasionally be blocked in some countries. To make sure that our users are able to communicate and learn freely, we need to understand these patterns, see who is affected, and work with partners to make sure their services work best with Psiphon.", @"Bullet list text under 'Why does Psiphon need these statistics?' subsection of the 'User VPN Data' section of the Privacy page. (English is using 'who' instead of 'whom' to reflect common idiom.)"),
    ]];

    // Add bullets to section 3 body items
    for (NSUInteger i = 0; i < [sec3BodyItems count]; i++) {
        sec3BodyItems[i] = [NSString stringWithFormat:@"\u2022  %@", sec3BodyItems[i]];
    }
    NSString *sec3BodyTop = NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhydoespsiphonneedPara1ListStart", nil, [NSBundle mainBundle], @"This data is used by us to determine how our network is being used. This allows us to do things like:", @"Paragraph text in the 'Why does Psiphon need these statistics?' subsection of the 'User VPN Data' section of the Privacy page. This paragraph serves as preamble for a detailed list, which is why it ends with a colon.");

    SectionView *sec3 = [[SectionView alloc] init];
    sec3.anchorView = stackView;
    sec3.header.text = NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhydoespsiphonneedSubhead", nil, [NSBundle mainBundle], @"Why does Psiphon need these statistics?", @"Sub-heading in the 'User VPN Data' section of the Privacy Policy page. The section describes why Psiphon needs VPN data stats.");
    sec3.body.text = [NSString stringWithFormat:@"%@\n\n%@", sec3BodyTop, [sec3BodyItems componentsJoinedByString:@"\n\n"]];
    [self replaceLinksInTextView:sec3.body error:&e];
    if (e != nil) {
        [PsiFeedbackLogger error:@"%s failed to replace links: %@", __FUNCTION__, e.localizedDescription];
    }
    [stackView addArrangedSubview:sec3];
    [sec3 addViewsAndApplyConstraints];

    // Section 4
    NSArray *sec4BodyParagraphs = @[
      NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhopsiphonshareswithPara1", nil, [NSBundle mainBundle], @"When sharing with third parties, Psiphon only ever provides coarse, aggregate domain-bytes statistics. We never share per-session information or any other possibly-identifying information.", @"Paragraph text in the 'Who does Psiphon share these statistics with?' subsection of the 'User VPN Data' section of the Privacy page."),
      NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhopsiphonshareswithPara2", nil, [NSBundle mainBundle], @"This sharing is typically done with services or organizations we collaborate with — as <a href=\"http://www.dw.com/en/psiphon-helps-dodge-the-online-trackers/a-16765092\" target=\"_blank\">we did with DW</a> a few years ago. These statistics help us and them answer questions like, “how many bytes were transferred through Psiphon for DW.com to all users in Iran in April?”", @"Paragraph text in the 'Who does Psiphon share these statistics with?' subsection of the 'User VPN Data' section of the Privacy page."),
      NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhopsiphonshareswithPara3", nil, [NSBundle mainBundle], @"Again, we specifically do not give detailed or potentially user-identifying information to partners or any other third parties.", @"Paragraph text in the 'Who does Psiphon share these statistics with?' subsection of the 'User VPN Data' section of the Privacy page.")
    ];

    SectionView *sec4 = [[SectionView alloc] init];
    sec4.anchorView = stackView;
    sec4.header.text = NSLocalizedStringWithDefaultValue(@"PrivacyInformationCollectedVpndataWhopsiphonshareswithSubhead", nil, [NSBundle mainBundle], @"Who does Psiphon share these statistics with?", @"Sub-heading in the 'User VPN Data' section of the Privacy Policy page. The section describes who Psiphon shares VPN data stats. The answer will be organizations and not specific people, in case that makes a difference in your language.");
    sec4.body.text = [sec4BodyParagraphs componentsJoinedByString:@"\n\n"];
    [self replaceLinksInTextView:sec4.body error:&e];
    if (e != nil) {
        [PsiFeedbackLogger error:@"%s failed to replace links: %@", __FUNCTION__, e.localizedDescription];
    }

    [stackView addArrangedSubview:sec4];
    [sec4 addViewsAndApplyConstraints];

}

# pragma mark - UI Callbacks

- (void)onGetStartedTap {
    [self dismissViewControllerAnimated:TRUE completion:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:PrivacyPolicyDismissedNotification
                                                            object:nil
                                                          userInfo:@{PrivacyPolicyAcceptedNotificationBoolKey : @TRUE}];
    }];
}

- (void)onCancelTap {
    [self dismissViewControllerAnimated:TRUE completion:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:PrivacyPolicyDismissedNotification
                                                            object:nil
                                                          userInfo:@{PrivacyPolicyAcceptedNotificationBoolKey : @FALSE}];
    }];
}

/***
 *
 * Looks in target text view's text for html links of the form <a href="http://psiphon3.com">some text</a>.
 * If found these tags are removed and an attributed string is formed with these links. The text view is
 * then set to use this attributed string.
 *
 * Returns FALSE if an error occured
 */
- (BOOL)replaceLinksInTextView:(UITextView*)textView error:(NSError**)err {
    if (err == nil) {
        [NSError errorWithDomain:PrivacyPolicyErrorDomain code:PrivacyPolicyLinkGenerationInvalidErrorPointer];
        return FALSE;
    }

    NSString *openTag = @"<a[^>]+href=\"(.*?)\"[^>]*>";
    NSString *closeTag = @"</a>";

    *err = nil;

    NSRegularExpression *openTagRegex = [NSRegularExpression regularExpressionWithPattern:openTag options:0 error:err];
    if (*err != nil) {
        return FALSE;
    }

    NSRegularExpression *closeTagRegex = [NSRegularExpression regularExpressionWithPattern:closeTag options:0 error:err];
    if (*err != nil) {
        return FALSE;
    }

    NSString *textToProcess = textView.text;
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:@""];

    while (textToProcess.length > 0) {
        // Remove open tag
        NSArray<NSTextCheckingResult*> *openTagMatches = [openTagRegex matchesInString:textToProcess options:0 range:NSMakeRange(0, textToProcess.length)];
        if (openTagMatches == nil || openTagMatches.count == 0) {
            break;
        }

        NSTextCheckingResult *openTagMatch = [openTagMatches objectAtIndex:0];
        NSString *openTagText = [textToProcess substringWithRange:NSMakeRange(openTagMatch.range.location, openTagMatch.range.length)];
        textToProcess = [textToProcess stringByReplacingCharactersInRange:openTagMatch.range withString:@""];

        // Get link
        NSDataDetector *detect = [[NSDataDetector alloc] initWithTypes:NSTextCheckingTypeLink error:err];
        if (*err != nil) {
            return FALSE;
        }

        NSArray<NSTextCheckingResult*> *hrefMatches = [detect matchesInString:openTagText options:0 range:NSMakeRange(0, openTagText.length)];
        if (hrefMatches == nil || hrefMatches.count == 0) {
            *err = [NSError errorWithDomain:PrivacyPolicyErrorDomain code:PrivacyPolicyLinkGenerationFailedToFindHref];
            return FALSE;
        }

        NSTextCheckingResult *hrefMatch = [hrefMatches objectAtIndex:0];
        NSString *hrefText = [openTagText substringWithRange:NSMakeRange(hrefMatch.range.location, hrefMatch.range.length)];
        NSURL *url = [NSURL URLWithString:hrefText];
        if (url == nil) {
            *err = [NSError errorWithDomain:PrivacyPolicyErrorDomain code:PrivacyPolicyLinkGenerationFailedToGenerateURL];
            return FALSE;
        }

        // Remove close tag
        NSArray<NSTextCheckingResult*> *closeTagMatches = [closeTagRegex matchesInString:textToProcess options:0 range:NSMakeRange(0, textToProcess.length)];
        if (closeTagMatches == nil || closeTagMatches.count == 0) {
            *err = [NSError errorWithDomain:PrivacyPolicyErrorDomain code:PrivacyPolicyLinkGenerationFailedToFindCloseTag];
            return FALSE;
        }

        NSTextCheckingResult *closeTagMatch = [closeTagMatches objectAtIndex:0];
        textToProcess =  [textToProcess stringByReplacingCharactersInRange:closeTagMatch.range withString:@""];

        // Remove remaining text for next processing round
        NSString *chunkText = [textToProcess substringWithRange:NSMakeRange(0, closeTagMatch.range.location)];
        textToProcess = [textToProcess substringWithRange:NSMakeRange(closeTagMatch.range.location, textToProcess.length - closeTagMatch.range.location)];

        // Create link
        NSRange linkRange = NSMakeRange(openTagMatch.range.location, chunkText.length - openTagMatch.range.location);
        NSDictionary *linkAttributes = @{ NSLinkAttributeName: url, NSFontAttributeName: textView.font};

        NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:chunkText attributes:@{NSFontAttributeName: textView.font}];
        [attributedString setAttributes:linkAttributes range:linkRange];

        [attr appendAttributedString:attributedString];
    }

    if (attr.string.length > 0) {
        if (textToProcess.length != 0) {
            // Add remaining unprocessed text
            [attr appendAttributedString:[[NSAttributedString alloc] initWithString:textToProcess attributes:@{NSFontAttributeName:textView.font}]];
        }
        textView.attributedText = attr;
    }

    return TRUE;
}

@end
