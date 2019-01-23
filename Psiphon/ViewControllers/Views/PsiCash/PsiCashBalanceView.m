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

#import "PsiCashBalanceView.h"
#import "PsiCashClient.h"
#import "PsiCashSpeedBoostMeterView.h"
#import "ReactiveObjC.h"
#import "UIView+AutoLayoutViewGroup.h"

@interface PsiCashBalanceView ()
@property (atomic, readwrite) PsiCashClientModel *model;
@property (strong, nonatomic) UILabel *balance;
@property (strong, nonatomic) UIImageView *coin;
@end

#pragma mark -

@implementation PsiCashBalanceView {
    UIView *containerView;
    NSTimer *animationTimer;
}

-(void)setBounds:(CGRect)bounds{
    [super setFrame:bounds];
    [self setRoundedCornersWithBounds:bounds];
}

- (void)setRoundedCornersWithBounds:(CGRect)bounds {
    UIBezierPath* rounded = [UIBezierPath bezierPathWithRoundedRect:bounds byRoundingCorners:UIRectCornerTopLeft|UIRectCornerTopRight cornerRadii:CGSizeMake(5, 5)];
    CAShapeLayer* shape = [[CAShapeLayer alloc] init];
    [shape setPath:rounded.CGPath];
    self.layer.mask = shape;
}

- (void)setupViews {
    self.clipsToBounds = YES;
    self.layer.borderColor = [UIColor colorWithRed:0.94 green:0.96 blue:0.99 alpha:1.0].CGColor;
    self.layer.borderWidth = 2.f;
    self.backgroundColor = UIColor.whiteColor;

    // Setup container view
    containerView = [[UIView alloc] init];

    // Setup balance label
    _balance = [[UILabel alloc] init];
    _balance.backgroundColor = [UIColor clearColor];
    _balance.adjustsFontSizeToFitWidth = YES;
    _balance.font = [UIFont boldSystemFontOfSize:20];
    _balance.textAlignment = self.isRTL ? NSTextAlignmentRight : NSTextAlignmentLeft;
    _balance.textColor = [UIColor colorWithRed:0.30 green:0.31 blue:1.00 alpha:1.0];
    _balance.userInteractionEnabled = NO;

    // Setup coin graphic
    _coin = [[UIImageView alloc] init];
    _coin.contentMode = UIViewContentModeScaleAspectFit;
    _coin.image = [UIImage imageNamed:@"PsiCash_Coin"];
    [_coin.layer setMinificationFilter:kCAFilterTrilinear];
}

- (void)addSubviews {
    [self addSubview:containerView];
    [self addSubview:_balance];
    [self addSubview:_coin];
}

- (void)setupSubviewsLayoutConstraints {
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [containerView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [containerView.leadingAnchor constraintEqualToAnchor:_coin.leadingAnchor].active = YES;
    [containerView.trailingAnchor constraintEqualToAnchor:_balance.trailingAnchor].active = YES;
    [containerView.heightAnchor constraintEqualToAnchor:self.heightAnchor].active = YES;

    _balance.translatesAutoresizingMaskIntoConstraints = NO;
    [_balance.widthAnchor constraintGreaterThanOrEqualToAnchor:_coin.widthAnchor].active = YES;
    [_balance.leadingAnchor constraintEqualToAnchor:_coin.trailingAnchor constant:10].active = YES;
    [_balance.trailingAnchor constraintLessThanOrEqualToAnchor:containerView.trailingAnchor].active = YES;
    [_balance.centerYAnchor constraintEqualToAnchor:_coin.centerYAnchor].active = YES;

    _coin.translatesAutoresizingMaskIntoConstraints = NO;
    [_coin.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.9].active = YES;
    [_coin.widthAnchor constraintEqualToAnchor:self.heightAnchor].active = YES;
    [_coin.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = YES;
    [_coin.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor].active = YES;
    [_coin.trailingAnchor constraintEqualToAnchor:_balance.leadingAnchor constant:-10].active = YES;
}

- (NSTimer*)animateBalanceChangeFrom:(NSNumber*)previousBalance toNewBalance:(NSNumber*)newBalance {
    NSComparisonResult equality = [previousBalance compare:newBalance];
    if (equality == NSOrderedSame) {
        return nil; // nothing to animate
    }

    __block double currentBalance = previousBalance.doubleValue;
    double chunks = equality == NSOrderedAscending ? 1e9 : -1e9;
    double balanceDiff = newBalance.doubleValue - currentBalance;

    NSTimeInterval animationTime = 1;
    NSTimeInterval animationIntervals = (animationTime * chunks) / balanceDiff;
    NSTimeInterval minAnimationInterval = 0.01;

    if (animationIntervals < minAnimationInterval) {
        chunks = 1e9 * roundf((balanceDiff * minAnimationInterval) / (animationTime * 1e9));
        animationIntervals = minAnimationInterval;
    }

    return [NSTimer scheduledTimerWithTimeInterval:animationIntervals repeats:YES block:^(NSTimer * _Nonnull timer) {
        currentBalance += chunks;
        _balance.text = [PsiCashClientModel formattedBalance:[NSNumber numberWithDouble:currentBalance]];

        BOOL done = FALSE;
        if (chunks >= 0 && currentBalance >= self.model.balance.doubleValue) {
            done = TRUE;
        } else if (chunks < 0 && currentBalance <= self.model.balance.doubleValue) {
            done = TRUE;
        }

        if (done) {
            _balance.text = [PsiCashClientModel formattedBalance:self.model.balance];
            [timer invalidate];
        }
    }];
}

#pragma mark - State Changes

- (void)bindWithModel:(PsiCashClientModel*)clientModel {
    NSNumber *previousBalance = self.model.balance;
    self.model = clientModel;

    if ([self.model hasAuthPackage]) {
        if ([self.model.authPackage hasIndicatorToken]) {
            if (previousBalance == nil) {
                _balance.text = [PsiCashClientModel formattedBalance:clientModel.balance];
            } else {
                _balance.text = [PsiCashClientModel formattedBalance:previousBalance];
                [animationTimer invalidate];
                animationTimer = [self animateBalanceChangeFrom:previousBalance toNewBalance:clientModel.balance];
            }
        } else {
            // First launch: the user has no indicator token
            _balance.text = [PsiCashClientModel formattedBalance:[NSNumber numberWithInteger:0]];
        }
    } else {
        // Do nothing
    }
}

@end
