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
#import "PsiCashBalanceView.h"
#import "PsiCashClient.h"
#import "PsiCashSpeedBoostMeterView.h"
#import "ReactiveObjC.h"
#import <AudioToolbox/AudioToolbox.h>

@interface PsiCashBalanceView ()
@property (atomic, readwrite) PsiCashClientModel *model;
@property (strong, nonatomic) UILabel *balance;
@property (strong, nonatomic) UIImageView *coin;
@end

#pragma mark -

@implementation PsiCashBalanceView

-(id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [self setupViews];
        [self addViews];
        [self setupLayoutConstraints];
    }

    return self;
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
    self.backgroundColor = [UIColor colorWithRed:0.38 green:0.27 blue:0.92 alpha:.12];
    self.contentEdgeInsets = UIEdgeInsetsMake(10.0f, 30.0f, 10.0f, 30.0f);

    // Setup balance label
    _balance = [[UILabel alloc] init];
    _balance.backgroundColor = [UIColor clearColor];
    _balance.font = [UIFont boldSystemFontOfSize:16];
    _balance.textAlignment = NSTextAlignmentCenter;
    _balance.textColor = [UIColor whiteColor];
    _balance.userInteractionEnabled = NO;

    // Setup coin graphic
    _coin = [[UIImageView alloc] init];
    _coin.image = [UIImage imageNamed:@"PsiCash_Coin"];
    [_coin.layer setMinificationFilter:kCAFilterTrilinear];
}

- (void)addViews {
    [self addSubview:_balance];
    [self addSubview:_coin];
}

- (void)setupLayoutConstraints {
    _balance.translatesAutoresizingMaskIntoConstraints = NO;
    [_balance.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [_balance.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;

    CGFloat coinSize = 30.f;
    _coin.translatesAutoresizingMaskIntoConstraints = NO;
    [_coin.heightAnchor constraintEqualToConstant:coinSize].active = YES;
    [_coin.widthAnchor constraintEqualToConstant:coinSize].active = YES;
    [_coin.centerYAnchor constraintEqualToAnchor:_balance.centerYAnchor].active = YES;
    [_coin.trailingAnchor constraintEqualToAnchor:_balance.leadingAnchor constant:-5].active = YES;

}

- (void)earnAnimation {
    CABasicAnimation *animation =
    [CABasicAnimation animationWithKeyPath:@"position"];
    [animation setDuration:0.1];
    [animation setRepeatCount:1];
    [animation setAutoreverses:YES];
    [animation setRemovedOnCompletion:YES];

    [animation setFromValue:[NSValue valueWithCGPoint:
                             CGPointMake([_coin center].x, [_coin center].y)]];
    [animation setToValue:[NSValue valueWithCGPoint:
                           CGPointMake([_coin center].x, [_coin center].y - 10.f)]];

    [[_coin layer] addAnimation:animation forKey:@"position"];
}

#pragma mark - State Changes

- (NSString*)stringFromBalance:(double)balance {
    return [NSString stringWithFormat:@"%.0f", balance / 1e9];
}

- (void)bindWithModel:(PsiCashClientModel*)clientModel {
    self.model = clientModel;

    if ([self.model hasAuthPackage]) {
        if ([self.model.authPackage hasIndicatorToken]) {
            _balance.text = [self stringFromBalance:clientModel.balanceInNanoPsi];
        } else {
            // First launch: the user has no indicator token
            _balance.text = [self stringFromBalance:0];
        }
    } else {
        // Do nothing
    }
}

@end
