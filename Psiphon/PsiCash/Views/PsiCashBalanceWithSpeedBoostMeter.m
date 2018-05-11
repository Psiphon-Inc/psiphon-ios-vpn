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

#import "PsiCashBalanceWithSpeedBoostMeter.h"
#import "PsiCashBalanceView.h"
#import "PsiCashSpeedBoostMeterView.h"
#import "PsiCashClient.h"
#import "ReactiveObjC.h"

@interface PsiCashBalanceWithSpeedBoostMeter ()
@property (atomic, readwrite) PsiCashClientModel *model;
@end

@implementation PsiCashBalanceWithSpeedBoostMeter {
    UIImageView *coin;
    PsiCashBalanceView *balance;
    PsiCashSpeedBoostMeterView *meter;
}

-(id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [self setupViews];
        [self addViews];
        [self setupLayoutConstraints];
    }

    return self;
}

- (void)setupViews {
    [self setBackgroundColor:[UIColor clearColor]];

    // Setup balance View
    balance = [[PsiCashBalanceView alloc] init];

    // Setup Speed Boost meter
    meter = [[PsiCashSpeedBoostMeterView alloc] init];
}

- (void)addViews {
    [self addSubview:coin];
    [self addSubview:balance];
    [self addSubview:meter];
}

- (void)setupLayoutConstraints {
    balance.translatesAutoresizingMaskIntoConstraints = NO;
    [balance.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [balance.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
    [balance.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.5].active = YES;
    [balance.heightAnchor constraintEqualToConstant:40.f].active = YES;

    meter.translatesAutoresizingMaskIntoConstraints = NO;
    [meter.centerXAnchor constraintEqualToAnchor:balance.centerXAnchor].active = YES;
    [meter.topAnchor constraintEqualToAnchor:balance.bottomAnchor].active = YES;
    [meter.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.9].active = YES;
    [meter.heightAnchor constraintEqualToConstant:50.f].active = YES;
}

- (void)bindWithModel:(PsiCashClientModel *)clientModel {
    [balance bindWithModel:clientModel];
    [meter bindWithModel:clientModel];
}

@end
