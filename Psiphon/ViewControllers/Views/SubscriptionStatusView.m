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
        subStatusLabel.textColor = UIColor.whiteColor;
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

- (void)setTitle:(NSString *_Nonnull)title {
    statusLabel.attributedText = [self styleHeaderText:title];
}

- (void)setSubtitle:(NSString *_Nonnull)subtitle {
    subStatusLabel.text = subtitle;
}

- (NSAttributedString*)styleHeaderText:(NSString*)s {
    NSMutableAttributedString *mutableStr = [[NSMutableAttributedString alloc] initWithString:s];
    [mutableStr addAttribute:NSKernAttributeName
                       value:@1
                       range:NSMakeRange(0, mutableStr.length)];
    return mutableStr;
}

@end
