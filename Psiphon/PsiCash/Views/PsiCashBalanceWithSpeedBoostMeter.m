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
#import "PsiCashClient.h"
#import "ReactiveObjC.h"

@interface PsiCashBalanceWithSpeedBoostMeter ()
@property (atomic, readwrite) PsiCashClientModel *model;
@property (strong, nonatomic) PsiCashBalanceView *balance;
@property (strong, nonatomic) PsiCashSpeedBoostMeterView *meter;
@end

@implementation PsiCashBalanceWithSpeedBoostMeter {
    UIActivityIndicatorView *activityIndicator;
    UIImageView *coin;
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
    _balance = [[PsiCashBalanceView alloc] init];

    // Setup Speed Boost meter
    _meter = [[PsiCashSpeedBoostMeterView alloc] init];

    // Setup activity indicator
    activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
}

- (void)addViews {
    [self addSubview:coin];
    [self addSubview:_balance];
    [self addSubview:_meter];
    [self addSubview:activityIndicator];
}

- (void)setupLayoutConstraints {
    _balance.translatesAutoresizingMaskIntoConstraints = NO;
    [_balance.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [_balance.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
    [_balance.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.5].active = YES;
    [_balance.heightAnchor constraintEqualToConstant:40.f].active = YES;

    _meter.translatesAutoresizingMaskIntoConstraints = NO;
    [_meter.centerXAnchor constraintEqualToAnchor:_balance.centerXAnchor].active = YES;
    [_meter.topAnchor constraintEqualToAnchor:_balance.bottomAnchor].active = YES;
    [_meter.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.9].active = YES;
    [_meter.heightAnchor constraintEqualToConstant:50.f].active = YES;

    activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [activityIndicator.leadingAnchor constraintEqualToAnchor:_balance.balance.trailingAnchor constant:0].active = YES;
    [activityIndicator.centerYAnchor constraintEqualToAnchor:_balance.centerYAnchor constant:2].active = YES;
}

- (void)bindWithModel:(PsiCashClientModel *)clientModel {
    if (clientModel.refreshPending) {
        [activityIndicator startAnimating];
    } else {
        [activityIndicator stopAnimating];
    }
    [_balance bindWithModel:clientModel];
    [_meter bindWithModel:clientModel];
}

#pragma mark - animation helpers

+ (void)animateBalanceChangeOf:(NSNumber*)delta withPsiCashView:(PsiCashBalanceWithSpeedBoostMeter*)psiCashView inParentView:(UIView*)parentView {
    UILabel *changeLabel = [[UILabel alloc] init];
    changeLabel.textAlignment = NSTextAlignmentLeft;
    changeLabel.adjustsFontSizeToFitWidth = YES;
    if ([delta doubleValue] > 0) {
        changeLabel.text = [NSString stringWithFormat:@"+%@", [PsiCashClientModel formattedBalance:delta]];
        changeLabel.textColor = [UIColor colorWithRed:0.15 green:0.90 blue:0.51 alpha:1.0];
    } else {
        changeLabel.text = [PsiCashClientModel formattedBalance:delta];
        changeLabel.textColor = [UIColor colorWithRed:0.55 green:0.72 blue:1.00 alpha:1.0];
    }
    changeLabel.translatesAutoresizingMaskIntoConstraints = NO;

    changeLabel.font = [UIFont systemFontOfSize:16];
    [parentView addSubview:changeLabel];

    [changeLabel.leadingAnchor constraintEqualToAnchor:psiCashView.balance.balance.trailingAnchor constant:0].active = YES;
    [changeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:parentView.trailingAnchor constant:10].active = YES;
    NSLayoutConstraint *centerY = [changeLabel.centerYAnchor constraintEqualToAnchor:psiCashView.balance.centerYAnchor constant:2];
    centerY.active = YES;
    [parentView layoutIfNeeded];

    changeLabel.alpha = 0;
    centerY.constant = -10;
    [UIView animateKeyframesWithDuration:1.5 delay:0 options:UIViewKeyframeAnimationOptionCalculationModeLinear animations:^{
        [UIView addKeyframeWithRelativeStartTime:0 relativeDuration:0.5 animations:^{
            changeLabel.alpha = 1;
            [parentView layoutIfNeeded];
            centerY.constant = -20;
        }];
        [UIView addKeyframeWithRelativeStartTime:0.5 relativeDuration:0.5 animations:^{
            changeLabel.transform = CGAffineTransformScale(changeLabel.transform, 2, 2);
            changeLabel.alpha = 0;
            [parentView layoutIfNeeded];
        }];
    } completion:^(BOOL finished) {
        [changeLabel removeFromSuperview];
    }];
}

@end
