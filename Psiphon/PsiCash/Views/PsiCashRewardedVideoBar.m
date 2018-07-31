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

#import "PsiCashRewardedVideoBar.h"
#import "PsiCashClient.h"
#import "PsiCashSpeedBoostMeterView.h"
#import "ReactiveObjC.h"

@interface PsiCashRewardedVideoBar ()
@end

#pragma mark -

@implementation PsiCashRewardedVideoBar {
    UIImageView *coinBundle;
    UIImageView *playSymbol;
    UILabel *status;
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

-(void)setBounds:(CGRect)bounds{
    [super setFrame:bounds];
    [self setRoundedCornersWithBounds:bounds];
}

- (void)setRoundedCornersWithBounds:(CGRect)bounds {
    UIBezierPath* rounded = [UIBezierPath bezierPathWithRoundedRect:bounds byRoundingCorners:UIRectCornerAllCorners cornerRadii:CGSizeMake(5, 5)];
    CAShapeLayer* shape = [[CAShapeLayer alloc] init];
    [shape setPath:rounded.CGPath];
    self.layer.mask = shape;
}

- (void)setupViews {
    self.clipsToBounds = YES;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:.40];
    self.contentEdgeInsets = UIEdgeInsetsMake(10.0f, 30.0f, 10.0f, 30.0f);
    
    // Setup coin bundle image view
    coinBundle = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PsiCash_PlayButton"]];
    coinBundle.contentMode = UIViewContentModeScaleAspectFit;
    coinBundle.layer.minificationFilter = kCAFilterTrilinear;
    
    // Setup coin play symbol image view
    playSymbol = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PsiCash_CoinBundle"]];
    playSymbol.contentMode = UIViewContentModeScaleAspectFit;
    playSymbol.layer.minificationFilter = kCAFilterTrilinear;
    
    // Setup status label
    status = [[UILabel alloc] init];
    status.backgroundColor = [UIColor clearColor];
    status.adjustsFontSizeToFitWidth = YES;
    status.font = [UIFont boldSystemFontOfSize:20];
    status.textAlignment = NSTextAlignmentCenter;
    status.textColor = [UIColor whiteColor];
    status.userInteractionEnabled = NO;
    
    status.text = @"Watch a video to earn PsiCash!";
    status.textColor = [UIColor colorWithRed:1.00 green:0.91 blue:0.55 alpha:1.0];
}

- (void)addViews {
    [self addSubview:coinBundle];
    [self addSubview:playSymbol];
    [self addSubview:status];
}

- (void)setupLayoutConstraints {
    coinBundle.translatesAutoresizingMaskIntoConstraints = NO;
    [coinBundle.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10].active = YES;
    [coinBundle.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [coinBundle.widthAnchor constraintEqualToConstant:17].active = YES;
    [coinBundle.heightAnchor constraintEqualToConstant:17].active = YES;
    
    playSymbol.translatesAutoresizingMaskIntoConstraints = NO;
    [playSymbol.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:0].active = YES;
    [playSymbol.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [playSymbol.widthAnchor constraintEqualToConstant:40].active = YES;
    [playSymbol.heightAnchor constraintEqualToConstant:20].active = YES;
    
    status.translatesAutoresizingMaskIntoConstraints = NO;
    [status.leadingAnchor constraintEqualToAnchor:coinBundle.trailingAnchor constant:5].active = YES;
    [status.trailingAnchor constraintEqualToAnchor:playSymbol.leadingAnchor constant:0].active = YES;
    [status.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:0].active = YES;
    [status.heightAnchor constraintEqualToAnchor:self.heightAnchor constant:0].active = YES;
}

@end
