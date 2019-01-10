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

#import "SubscriptionsBar.h"
#import "WhiteSkyButton.h"
#import "SubscriptionStatusView.h"
#import "Strings.h"

@implementation SubscriptionsBar {
    WhiteSkyButton *manageSubscriptionsButton;
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
        stackView.userInteractionEnabled = FALSE;

        subscriptionStatusViewContainer = [[UIView alloc] init];

        subscriptionStatusView = [[SubscriptionStatusView alloc] init];

        manageSubscriptionButtonContainer = [[UIView alloc] init];

        manageSubscriptionsButton = [[WhiteSkyButton alloc] initForAutoLayout];
        manageSubscriptionsButton.shadow = TRUE;

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
    [stackView.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.9].active = YES;
    [stackView.heightAnchor constraintEqualToAnchor:self.heightAnchor].active = YES;
    [stackView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [stackView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;

    subscriptionStatusView.translatesAutoresizingMaskIntoConstraints = NO;
    [subscriptionStatusView.centerXAnchor constraintEqualToAnchor:subscriptionStatusViewContainer.centerXAnchor].active = YES;
    [subscriptionStatusView.centerYAnchor constraintEqualToAnchor:subscriptionStatusViewContainer.centerYAnchor].active = YES;
    [subscriptionStatusView.widthAnchor constraintEqualToAnchor:subscriptionStatusViewContainer.widthAnchor multiplier:0.712].active = YES;
    [subscriptionStatusView.heightAnchor constraintEqualToAnchor:subscriptionStatusViewContainer.heightAnchor multiplier:0.456].active = YES;

    manageSubscriptionsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [manageSubscriptionsButton.centerXAnchor constraintEqualToAnchor:manageSubscriptionButtonContainer.centerXAnchor].active = YES;
    [manageSubscriptionsButton.centerYAnchor constraintEqualToAnchor:manageSubscriptionButtonContainer.centerYAnchor].active = YES;
    [manageSubscriptionsButton.widthAnchor constraintEqualToAnchor:manageSubscriptionButtonContainer.widthAnchor multiplier:0.732].active = YES;
    [manageSubscriptionsButton.heightAnchor constraintEqualToAnchor:manageSubscriptionButtonContainer.heightAnchor multiplier:0.481].active = YES;
}

- (void)subscriptionActive:(BOOL)subscriptionActive {
    if (subscriptionActive) {
        [manageSubscriptionsButton setTitle:[Strings manageSubscriptionButtonTitle]];
    } else {
        [manageSubscriptionsButton setTitle:[Strings subscribeButtonTitle]];
    }

    [subscriptionStatusView subscriptionActive:subscriptionActive];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [manageSubscriptionsButton touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [manageSubscriptionsButton touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [manageSubscriptionsButton touchesCancelled:touches withEvent:event];
}

@end
