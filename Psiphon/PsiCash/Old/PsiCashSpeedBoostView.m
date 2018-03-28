/*
 * Copyright (c) 2017, Psiphon Inc.
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

#import "PsiCashSpeedBoostView.h"
#import "PsiCashClient.h"
#import "ReactiveObjC.h"

#import "psicash.hpp"
#import "types.hpp"

@implementation PsiCashSpeedBoostView {
    UIStackView *stackView;

    // AccountNotSpeedboosting views
    UILabel *info;
    UISlider *slider;
    UIButton *buySpeedBoost;

    // AccountSpeedboosting views
    UILabel *speedBoosting;
}

-(id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [self setupViews];
        [self setupLayoutConstraints];
        [self startObserving];
    }

    return self;
}

- (void)setupViews {
    // StackView reused for all states
    stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.spacing = 10.f;

    // AccountNotSpeedboosting views
    info = [[UILabel alloc] init];
    info.adjustsFontSizeToFitWidth = YES;
    info.font = [UIFont systemFontOfSize:14.f];
    info.numberOfLines = 0;
    info.text = @"Want a blazing fast connection? Use SpeedBoost™!";
    info.textColor = [UIColor whiteColor];
    info.textAlignment = NSTextAlignmentCenter;

    slider = [[UISlider alloc] init];
    slider.value = 0.0f;
    [slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self sliderValueChanged:slider]; // TOOD: fire once from here?

    // TOOD: cleanup
    buySpeedBoost = [[UIButton alloc] init];
    [buySpeedBoost setTitle:@"Buy and start speedboosting!" forState:UIControlStateNormal];
    [buySpeedBoost.titleLabel setFont:[UIFont systemFontOfSize:16.f]];
    [buySpeedBoost setContentEdgeInsets:UIEdgeInsetsMake(5, 5, 5, 5)];
    [buySpeedBoost setBackgroundColor:[UIColor colorWithRed:0.82 green:0.43 blue:0.41 alpha:1.0]];
    [buySpeedBoost.layer setCornerRadius:5.f];
    [buySpeedBoost.layer setBorderColor:[UIColor colorWithRed:0.87 green:0.75 blue:0.62 alpha:1.0].CGColor];
    [buySpeedBoost.layer setBorderWidth:1.f];

    [buySpeedBoost addTarget:self action:@selector(purchaseSpeedBoost) forControlEvents:UIControlEventTouchUpInside]; // TODO: better location?

    // AccountSpeedboosting views

}

- (void)clearStackView {
    for (UIView *subview in stackView.subviews) {
        [subview removeFromSuperview];
    }
}

- (void)addAccountNotSpeedboostingViews {
    [stackView addArrangedSubview:[UIView new]]; // TODO: is this a hack?
    [stackView addArrangedSubview:info];
    [stackView addArrangedSubview:slider];
    [stackView addArrangedSubview:buySpeedBoost];
    [stackView addArrangedSubview:[UIView new]];
    [self setupAccountNotSpeedboostingConstraints];
}

- (void)addAccountSpeedboostingViews {
    if (speedBoosting == nil) {
        // TODO: setup once in viewDidLoad?
        speedBoosting = [[UILabel alloc] init];
        speedBoosting.text = [NSString stringWithFormat:@"%f hours remaining", [[PsiCashClient sharedInstance] speedBoostTimeRemaining]];
        speedBoosting.textColor = [UIColor whiteColor];
    }

    [stackView addArrangedSubview:speedBoosting];
}

-  (void)setupLayoutConstraints {
    [self addSubview:stackView];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = YES;
    [stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
    [stackView.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
    [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = YES;
}

- (void)setupAccountNotSpeedboostingConstraints {
    info.translatesAutoresizingMaskIntoConstraints = NO;
    [info.centerXAnchor constraintEqualToAnchor:stackView.centerXAnchor].active = YES;
    [info.widthAnchor constraintEqualToAnchor:stackView.widthAnchor multiplier:0.75].active = YES;

    slider.translatesAutoresizingMaskIntoConstraints = NO;
    [slider.centerXAnchor constraintEqualToAnchor:stackView.centerXAnchor].active = YES;
    [slider.widthAnchor constraintEqualToAnchor:stackView.widthAnchor multiplier:0.5].active = YES;

    buySpeedBoost.translatesAutoresizingMaskIntoConstraints = NO;
    [buySpeedBoost.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
}

- (void)setupAccountSpeedboostingConstraints {

}

- (void)startObserving {
    [RACObserve([PsiCashClient sharedInstance], balanceInNanoPsi) subscribeNext:^(NSNumber *newBalance) {
        [self updateCanBuy];
    }];

    [RACObserve([PsiCashClient sharedInstance], speedBoostTimePerOnePsiCash) subscribeNext:^(NSNumber *newExchangeRate) {
        [self sliderValueChanged:slider];
    }];

    [RACObserve([PsiCashClient sharedInstance], speedBoostTimeRemaining) subscribeNext:^(NSNumber *newTimeRemaining) {
        if ([[PsiCashClient sharedInstance] state] == SpeedBoosting) {
            // TODO: this is a terrible hack
            speedBoosting.text = [NSString stringWithFormat:@"%@ hours remaining", newTimeRemaining];
        }
    }];

    [RACObserve([PsiCashClient sharedInstance],state) subscribeNext:^(NSNumber *newClientState) {
        switch ([newClientState integerValue]) {
            case Unknown:
                [self enterNoAccountState];
                break;
            case NotSpeedBoosting:
                [self enterAccountNotSpeedBoostingState];
                break;
            case SpeedBoosting:
                [self enterAccountSpeedboostingState];
                break;
            default:
                break;
        }
    }];
}

-(void)enterNoAccountState {
    // TODO
}

- (void)enterAccountNotSpeedBoostingState {
    [self clearStackView];
    [self addAccountNotSpeedboostingViews];
}

- (void)enterAccountSpeedboostingState {
    [self clearStackView];
    [self addAccountSpeedboostingViews];
}

- (void)sliderValueChanged:(UISlider *)sender {
    int num_hours = [self sliderNumHours:sender.value];
    float cost = [self quoteForPurchase:num_hours];

    // TODO: less frequent updates to the UI
    if (num_hours > 1) {
        info.text = [NSString stringWithFormat:@"%d hours of SpeedBoost = %.2f PsiCash", num_hours, cost];
    } else {
        info.text = [NSString stringWithFormat:@"%d hour of SpeedBoost = %.2f PsiCash", num_hours, cost];
    }

    [self updateCanBuy];
}

- (void)updateCanBuy {
    uint num_hours = 1 + (int)(7 * slider.value);
    uint hours_available_for_purchase = [[PsiCashClient sharedInstance] hoursAvailableForPurchase];
    if (hours_available_for_purchase >= num_hours && [[PsiCashClient sharedInstance] state] == NotSpeedBoosting /* TODO */) {
        buySpeedBoost.enabled = YES;
        buySpeedBoost.alpha = 1;
    } else {
        buySpeedBoost.enabled = NO;
        buySpeedBoost.alpha = .5f;
    }
}

// TODO: clean all the below up
- (int)sliderNumHours:(float)slider_value {
    int num_hours = 1 + (int)(7 * slider_value);
    return num_hours;
}

- (float)quoteForPurchase:(int)num_hours {
    return num_hours * [[PsiCashClient sharedInstance] speedBoostTimePerOnePsiCash];
}

- (void)purchaseSpeedBoost {
    [[PsiCashClient sharedInstance] purchaseSpeedBoost:[self sliderNumHours:slider.value]];
}

@end
