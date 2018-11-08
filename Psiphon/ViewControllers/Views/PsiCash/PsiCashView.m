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

#import "PsiCashView.h"
#import "PsiCashClient.h"
#import "ReactiveObjC.h"
#import "UIColor+Additions.h"
#import "UIFont+Additions.h"
#import "UIView+AutoLayoutViewGroup.h"
#import "RoyalSkyButton.h"

@interface PsiCashView ()
@property (atomic, readwrite) PsiCashClientModel *model;
@property (strong, nonatomic) PsiCashBalanceView *balance;
@property (strong, nonatomic) PsiCashSpeedBoostMeterView *meter;
@end

@implementation PsiCashView {
    UIActivityIndicatorView *activityIndicator;
    UIImageView *coin;
    UIView *topBorderBlocker;
    UIView *bottomBorderBlocker;
}

+ (NSString *)videoReadyTitleText {
    return NSLocalizedStringWithDefaultValue(@"REWARDED_VIDEO_EARN_PSICASH", nil,
      [NSBundle mainBundle],
      @"Watch a video to earn PsiCash!",
      @"Button label indicating to the user that they will earn PsiCash if they watch a video "
      "advertisement. The word 'PsiCash' should not be translated or transliterated.");
}

+ (NSString *)videoUnavailableTitleText {
    return NSLocalizedStringWithDefaultValue(@"REWARDED_VIDEO_NO_VIDEOS_AVAILABLE", nil,
      [NSBundle mainBundle],
      @"No Videos Available",
      @"Button label indicating to the user that there are no videos available for them to watch.");
}

- (void)setupViews {
    [self setBackgroundColor:[UIColor clearColor]];

    // Setup balance View
    _balance = [[PsiCashBalanceView alloc] initWithAutoLayout];

    // Setup Speed Boost meter
    _meter = [[PsiCashSpeedBoostMeterView alloc] initWithAutoLayout];

    // Setup activity indicator
    activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];

    // Setup rewarded video button
    _rewardedVideoButton = [[RoyalSkyButton alloc] initWithAutoLayout];
    [_rewardedVideoButton setTitle:[PsiCashView videoReadyTitleText]
                          forState:UIControlStateNormal];
    [_rewardedVideoButton setTitle:[PsiCashView videoUnavailableTitleText]
                          forState:UIControlStateDisabled];
    _rewardedVideoButton.enabled = FALSE;

    topBorderBlocker = [[UIView alloc] init];
    topBorderBlocker.backgroundColor = [UIColor whiteColor];

    bottomBorderBlocker = [[UIView alloc] init];
    bottomBorderBlocker.backgroundColor = [UIColor whiteColor];
}

- (void)addSubviews {
    [self addSubview:coin];
    [self addSubview:_balance];
    [self addSubview:_meter];
    [self addSubview:activityIndicator];
    [self addSubview:_rewardedVideoButton];
    [self addSubview:topBorderBlocker];
    [self addSubview:bottomBorderBlocker];
}

- (void)setupSubviewsLayoutConstraints {
    _balance.translatesAutoresizingMaskIntoConstraints = NO;
    [_balance.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [_balance.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
    [_balance.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.5498].active = YES;
    [_balance.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:40.0/152].active = YES;

    _meter.translatesAutoresizingMaskIntoConstraints = NO;
    [_meter.centerXAnchor constraintEqualToAnchor:_balance.centerXAnchor].active = YES;
    [_meter.topAnchor constraintEqualToAnchor:_balance.bottomAnchor constant:-2].active = YES;
    [_meter.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
    [_meter.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:60.0/152].active = YES;

    activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [activityIndicator.leadingAnchor constraintEqualToAnchor:_balance.balance.trailingAnchor constant:0].active = YES;
    [activityIndicator.centerYAnchor constraintEqualToAnchor:_balance.centerYAnchor constant:2].active = YES;

    _rewardedVideoButton.translatesAutoresizingMaskIntoConstraints = NO;

    [_rewardedVideoButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [_rewardedVideoButton.topAnchor constraintEqualToAnchor:_meter.bottomAnchor constant:-2].active = YES;
    [_rewardedVideoButton.widthAnchor constraintEqualToAnchor:_meter.widthAnchor multiplier:0.80687].active = YES;
    [_rewardedVideoButton.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:52.0/152].active = YES;

    topBorderBlocker.translatesAutoresizingMaskIntoConstraints = NO;
    [topBorderBlocker.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [topBorderBlocker.topAnchor constraintEqualToAnchor:_meter.topAnchor].active = YES;
    [topBorderBlocker.widthAnchor constraintEqualToAnchor:_balance.widthAnchor constant:-4.f].active = YES;
    [topBorderBlocker.heightAnchor constraintEqualToConstant:4.f].active = YES;

    bottomBorderBlocker.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomBorderBlocker.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [bottomBorderBlocker.topAnchor constraintEqualToAnchor:_rewardedVideoButton.topAnchor].active = YES;
    [bottomBorderBlocker.widthAnchor constraintEqualToAnchor:_rewardedVideoButton.widthAnchor constant:-4.f].active = YES;
    [bottomBorderBlocker.heightAnchor constraintEqualToConstant:2.f].active = YES;
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

+ (void)animateBalanceChangeOf:(NSNumber*_Nonnull)delta withPsiCashView:(PsiCashView*)psiCashView inParentView:(UIView*)parentView {
    UILabel *changeLabel = [[UILabel alloc] init];
    changeLabel.textAlignment = NSTextAlignmentLeft;
    changeLabel.adjustsFontSizeToFitWidth = YES;
    if ([delta doubleValue] > 0) {
        changeLabel.text = [NSString stringWithFormat:@"+%@", [PsiCashClientModel formattedBalance:delta]];
        changeLabel.textColor = UIColor.lightTurquoise;
    } else {
        changeLabel.text = [PsiCashClientModel formattedBalance:delta];
        changeLabel.textColor = [UIColor colorWithRed:0.55 green:0.72 blue:1.00 alpha:1.0];
    }
    changeLabel.translatesAutoresizingMaskIntoConstraints = NO;

    changeLabel.font = [UIFont avenirNextBold:16];
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
