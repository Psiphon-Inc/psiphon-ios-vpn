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
    UIImageView *playButton;
    UIImageView *coinBundle;
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
    playButton = [[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"PsiCash_PlayButton"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    playButton.contentMode = UIViewContentModeScaleAspectFit;
    playButton.layer.minificationFilter = kCAFilterTrilinear;
    
    // Setup coin play symbol image view
    coinBundle = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PsiCash_CoinBundle"]];
    coinBundle.contentMode = UIViewContentModeScaleAspectFit;
    coinBundle.layer.minificationFilter = kCAFilterTrilinear;
    
    // Setup status label
    status = [[UILabel alloc] init];
    status.backgroundColor = [UIColor clearColor];
    status.adjustsFontSizeToFitWidth = YES;
    status.font = [UIFont boldSystemFontOfSize:20];
    status.textAlignment = NSTextAlignmentCenter;
    status.textColor = [UIColor whiteColor];
    status.userInteractionEnabled = NO;
    
    status.text = @"Watch a video to earn PsiCash!";

    // Assume at first that a video has not been loaded
    [self videoReady:NO];
}

- (void)addViews {
    [self addSubview:playButton];
    [self addSubview:coinBundle];
    [self addSubview:status];
}

- (void)setupLayoutConstraints {
    playButton.translatesAutoresizingMaskIntoConstraints = NO;
    [playButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10].active = YES;
    [playButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [playButton.widthAnchor constraintEqualToConstant:17].active = YES;
    [playButton.heightAnchor constraintEqualToConstant:17].active = YES;
    
    coinBundle.translatesAutoresizingMaskIntoConstraints = NO;
    [coinBundle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:0].active = YES;
    [coinBundle.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    [coinBundle.widthAnchor constraintEqualToConstant:40].active = YES;
    [coinBundle.heightAnchor constraintEqualToConstant:20].active = YES;
    
    status.translatesAutoresizingMaskIntoConstraints = NO;
    [status.leadingAnchor constraintEqualToAnchor:playButton.trailingAnchor constant:5].active = YES;
    [status.trailingAnchor constraintEqualToAnchor:coinBundle.leadingAnchor constant:0].active = YES;
    [status.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:0].active = YES;
    [status.heightAnchor constraintEqualToAnchor:self.heightAnchor constant:0].active = YES;
}

- (void)videoReady:(BOOL)ready {
    if (ready) {
        playButton.tintColor = [UIColor whiteColor];
        status.textColor = [UIColor whiteColor];
    } else {
        playButton.tintColor = [UIColor grayColor];
        status.textColor = [UIColor grayColor];
    }
}

@end
