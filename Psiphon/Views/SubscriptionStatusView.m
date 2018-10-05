//
//  SubscriptionStatusView.m
//  Psiphon
//
//  Created by Miro Kuratczyk on 2018-09-19.
//  Copyright © 2018 Psiphon Inc. All rights reserved.
//

#import "SubscriptionStatusView.h"
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
        statusLabel.text = @"GET PREMIUM";
        statusLabel.textAlignment = NSTextAlignmentLeft;
        statusLabel.textColor = [UIColor whiteColor];
        statusLabel.font = [UIFont avenirNextBold:13.f];

        subStatusLabel = [[UILabel alloc] init];
        subStatusLabel.adjustsFontSizeToFitWidth = YES;
        subStatusLabel.text = @"Remove ads";
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
        statusLabel.text = @"SUBSCRIPTION";
        subStatusLabel.text = @"Premium - Max Speed";
    } else {
        statusLabel.text = @"GET PREMIUM";
        subStatusLabel.text = @"Remove ads";
    }
}

@end
