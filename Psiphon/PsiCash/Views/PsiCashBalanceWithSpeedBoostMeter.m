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
}

- (void)addViews {
    [self addSubview:coin];
    [self addSubview:_balance];
    [self addSubview:_meter];
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
}

- (void)earnAnimation {
    [_balance earnAnimation];
}

- (void)bindWithModel:(PsiCashClientModel *)clientModel {
    [_balance bindWithModel:clientModel];
    [_meter bindWithModel:clientModel];
}

#pragma mark - Animation helpers

+ (void)earnAnimationWithCompletion:(UIView*)parentView andPsiCashView:(PsiCashBalanceWithSpeedBoostMeter*)targetPsiCashView andCompletion:(void (^)(void))completionHandler {
    CGFloat coinSize = targetPsiCashView.balance.coin.frame.size.width;
    UIImageView *coin = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PsiCash_Coin"]];
    coin.image = [UIImage imageNamed:@"PsiCash_Coin"];
    coin.layer.minificationFilter = kCAFilterTrilinear;

    coin.frame = CGRectMake(0, 0, coinSize, coinSize);
    CGPoint coinCenter = [targetPsiCashView.balance convertPoint:targetPsiCashView.balance.coin.center toView:parentView];
    coin.center = coinCenter;
    [parentView addSubview:coin];

    // Let PsiCashView execute its own earning animation first
    [targetPsiCashView earnAnimation];

    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [coin removeFromSuperview];
        completionHandler();
    }];

    // Create the coin's trajectory
    CGPoint arcStart = coinCenter;
    CGFloat arcRadius = 20;
    CGFloat arcHeight = 30;
    CGPoint arcCenter = CGPointMake(arcStart.x + arcRadius, arcStart.y - arcHeight);

    CGMutablePathRef arcPath = CGPathCreateMutable();
    CGPathMoveToPoint(arcPath, NULL, arcStart.x, arcStart.y);
    CGPathAddLineToPoint(arcPath, NULL, arcStart.x, arcStart.y - arcHeight);
    CGPathAddArc(arcPath, NULL, arcCenter.x, arcCenter.y, arcRadius, M_PI, 0, NO);
    CGPathAddLineToPoint(arcPath, NULL, arcCenter.x + arcRadius, arcStart.y + 50);

    // Create the animation
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    animation.calculationMode = kCAAnimationPaced;
    animation.path = arcPath;
    CGPathRelease(arcPath);
    [animation setAutoreverses:NO];
    [animation setDuration:.7];
    [animation setRepeatCount:0];
    [animation setRemovedOnCompletion:YES];

    // Add and start the animation
    [[coin layer] addAnimation:animation forKey:@"position"];
    [CATransaction commit];
}

@end
