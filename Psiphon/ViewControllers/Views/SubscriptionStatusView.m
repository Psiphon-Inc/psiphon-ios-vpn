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

#import "SubscriptionStatusView.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "UIFont+Additions.h"

@implementation SubscriptionStatusView {
    UIView *labelHolder;
    UIStackView *stackView;
    UILabel *statusLabel;
    UILabel *subStatusLabel;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        stackView = [[UIStackView alloc] init];
        stackView.axis = UILayoutConstraintAxisVertical;
        stackView.distribution = UIStackViewDistributionFillEqually;
        stackView.alignment = UIStackViewAlignmentLeading;

        labelHolder = [[UIView alloc] init];

        statusLabel = [[UILabel alloc] init];
        statusLabel.adjustsFontSizeToFitWidth = YES;
        statusLabel.textAlignment = NSTextAlignmentLeft;
        statusLabel.textColor = [UIColor whiteColor];
        statusLabel.font = [UIFont avenirNextBold:13.f];

        subStatusLabel = [[UILabel alloc] init];
        subStatusLabel.adjustsFontSizeToFitWidth = YES;
        subStatusLabel.textAlignment = NSTextAlignmentLeft;
        subStatusLabel.textColor = [UIColor colorWithWhite:1 alpha:.51f];
        subStatusLabel.font = [UIFont avenirNextDemiBold:13.f];

        [self addViews];
        [self addLayoutConstraints];
    }

    return self;
}

- (void)addViews {
    [self addSubview:labelHolder];
    [labelHolder addSubview:stackView];

    [stackView addArrangedSubview:statusLabel];
    [stackView addArrangedSubview:subStatusLabel];
}

- (void)addLayoutConstraints {
    labelHolder.translatesAutoresizingMaskIntoConstraints = NO;
    [labelHolder.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
    [labelHolder.heightAnchor constraintEqualToAnchor:self.heightAnchor].active = YES;
    [labelHolder.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [labelHolder.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;

    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [stackView.widthAnchor constraintEqualToAnchor:labelHolder.widthAnchor].active = YES;
    [stackView.heightAnchor constraintEqualToAnchor:labelHolder.heightAnchor].active = YES;
    [stackView.centerXAnchor constraintEqualToAnchor:labelHolder.centerXAnchor].active = YES;
    [stackView.centerYAnchor constraintEqualToAnchor:labelHolder.centerYAnchor].active = YES;
}

- (void)subscriptionActive:(BOOL)subscriptionActive {
    if (subscriptionActive) {
        NSString *headerText = NSLocalizedStringWithDefaultValue(@"SUBSCRIPTION_BAR_HEADER_TEXT_SUBSCRIBED",
                                                                 nil,
                                                                 [PsiphonClientCommonLibraryHelpers commonLibraryBundle],
                                                                 @"SUBSCRIPTION",
                                                                 @"Header text beside button that opens paid subscriptions manager UI. At this point the user is subscribed. Please keep this text concise as the width of the text box is restricted in size.");
        statusLabel.attributedText = [self styleHeaderText:headerText];
        subStatusLabel.text = NSLocalizedStringWithDefaultValue(@"SUBSCRIPTION_BAR_FOOTER_TEXT_SUBSCRIBED",
                                                                nil,
                                                                [PsiphonClientCommonLibraryHelpers commonLibraryBundle],
                                                                @"Premium - Max Speed",
                                                                @"Footer text beside button that opens paid subscriptions manager UI. At this point the user is subscribed. If “Premium” doesn't easily translate, please choose a term that conveys “Pro” or “Extra” or “Better” or “Elite”. Please keep this text concise as the width of the text box is restricted in size.");
    } else {
        NSString *headerText = NSLocalizedStringWithDefaultValue(@"SUBSCRIPTION_BAR_HEADER_TEXT_NOT_SUBSCRIBED",
                                                                 nil,
                                                                 [PsiphonClientCommonLibraryHelpers commonLibraryBundle],
                                                                 @"GET PREMIUM",
                                                                 @"Header text beside button that opens paid subscriptions manager UI. At this point the user is not subscribed. If “Premium” doesn't easily translate, please choose a term that conveys “Pro” or “Extra” or “Better” or “Elite”. Please keep this text concise as the width of the text box is restricted in size.");
        statusLabel.attributedText = [self styleHeaderText:headerText];
        subStatusLabel.text = NSLocalizedStringWithDefaultValue(@"SUBSCRIPTION_BAR_FOOTER_TEXT_NOT_SUBSCRIBED",
                                                                nil,
                                                                [PsiphonClientCommonLibraryHelpers commonLibraryBundle],
                                                                @"Remove ads",
                                                                @"Footer text beside button that opens paid subscriptions manager UI. At this point the user is not subscribed. Please keep this text concise as the width of the text box is restricted in size.");
    }
}

- (NSAttributedString*)styleHeaderText:(NSString*)s {
    NSMutableAttributedString *mutableStr = [[NSMutableAttributedString alloc] initWithString:s];
    [mutableStr addAttribute:NSKernAttributeName
                       value:@1
                       range:NSMakeRange(0, mutableStr.length)];
    return mutableStr;
}

@end
