//
//  SubscriptionsBar.m
//  Psiphon
//
//  Created by Miro Kuratczyk on 2018-09-19.
//  Copyright © 2018 Psiphon Inc. All rights reserved.
//

#import "SubscriptionsBar.h"
#import "ManageSubscriptionsButton.h"
#import "SubscriptionStatusView.h"

@implementation SubscriptionsBar {
    ManageSubscriptionsButton *manageSubscriptionsButton;
    SubscriptionStatusView *subscriptionStatusView;
    UIStackView *stackView;
    UIView *subscriptionStatusViewContainer;
    UIView *manageSubscriptionButtonContainer;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        stackView = [[UIStackView alloc] init];
        stackView.axis = UILayoutConstraintAxisHorizontal;
        stackView.distribution = UIStackViewDistributionFillEqually;
        stackView.userInteractionEnabled = NO;

        subscriptionStatusViewContainer = [[UIView alloc] init];

        subscriptionStatusView = [[SubscriptionStatusView alloc] init];

        manageSubscriptionButtonContainer = [[UIView alloc] init];

        manageSubscriptionsButton = [[ManageSubscriptionsButton alloc] init];

        manageSubscriptionsButton.layer.masksToBounds = NO;
        manageSubscriptionsButton.layer.shadowOffset = CGSizeMake(0, 2);
        manageSubscriptionsButton.layer.shadowOpacity = 0.2;
        manageSubscriptionsButton.layer.shadowRadius = 8;

        [self addViews];
        [self setupAutoLayoutConstraints];
    }

    return self;
}

- (void)addViews {
    [self addSubview:stackView];

    [subscriptionStatusViewContainer addSubview:subscriptionStatusView];
    [stackView addArrangedSubview:subscriptionStatusViewContainer];

    [manageSubscriptionButtonContainer addSubview:manageSubscriptionsButton];
    [stackView addArrangedSubview:manageSubscriptionButtonContainer];
}

- (void)setupAutoLayoutConstraints {
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [stackView.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
    [stackView.heightAnchor constraintEqualToAnchor:self.heightAnchor].active = YES;
    [stackView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [stackView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;

    subscriptionStatusView.translatesAutoresizingMaskIntoConstraints = NO;
    [subscriptionStatusView.centerXAnchor constraintEqualToAnchor:subscriptionStatusViewContainer.centerXAnchor].active = YES;
    [subscriptionStatusView.centerYAnchor constraintEqualToAnchor:subscriptionStatusViewContainer.centerYAnchor].active = YES;
    [subscriptionStatusView.widthAnchor constraintEqualToAnchor:subscriptionStatusViewContainer.widthAnchor multiplier:0.7125].active = YES;
    [subscriptionStatusView.heightAnchor constraintEqualToAnchor:subscriptionStatusViewContainer.heightAnchor multiplier:0.456].active = YES;

    manageSubscriptionsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [manageSubscriptionsButton.centerXAnchor constraintEqualToAnchor:manageSubscriptionButtonContainer.centerXAnchor].active = YES;
    [manageSubscriptionsButton.centerYAnchor constraintEqualToAnchor:manageSubscriptionButtonContainer.centerYAnchor].active = YES;
    [manageSubscriptionsButton.widthAnchor constraintEqualToAnchor:manageSubscriptionButtonContainer.widthAnchor multiplier:0.73].active = YES;
    [manageSubscriptionsButton.heightAnchor constraintEqualToAnchor:manageSubscriptionButtonContainer.heightAnchor multiplier:0.48].active = YES;

}

- (void)subscriptionActive:(BOOL)subscriptionActive {
    [manageSubscriptionsButton subscriptionActive:subscriptionActive];
    [subscriptionStatusView subscriptionActive:subscriptionActive];
}

@end
