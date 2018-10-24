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

#import "ManageSubscriptionsButton.h"
#import "UIFont+Additions.h"

@implementation ManageSubscriptionsButton

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        self.layer.cornerRadius = 8;
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor whiteColor];
        [self setTitleColor:[UIColor colorWithRed:0.30 green:0.31 blue:1.00 alpha:1.0] forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont avenirNextDemiBold:15.f];
    }

    return self;
}

- (void)subscriptionActive:(BOOL)subscriptionActive {
    if (subscriptionActive) {
        NSString *s = NSLocalizedStringWithDefaultValue(@"SUBSCRIPTIONS_MANAGE_SUBSCRIPTION_BUTTON", nil, [NSBundle mainBundle],
                                                        @"Manage",
                                                        @"Label on a button which, when pressed, opens a screen where the user can manage their currently active subscription.");
        [self setTitle:s forState:UIControlStateNormal];
    } else {
        NSString *s = NSLocalizedStringWithDefaultValue(@"SUBSCRIPTIONS_SUBSCRIBE_BUTTON", nil, [NSBundle mainBundle],
                                                        @"Subscribe",
                                                        @"Label on a button which, when pressed, opens a screen where the user can choose from multiple subscription plans.");
        [self setTitle:s forState:UIControlStateNormal];
    }
}

@end
