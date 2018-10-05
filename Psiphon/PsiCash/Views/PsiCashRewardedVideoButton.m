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

#import "PsiCashRewardedVideoButton.h"
#import "PsiCashClient.h"
#import "PsiCashSpeedBoostMeterView.h"
#import "ReactiveObjC.h"
#import "UIColor+Additions.h"
#import "UIFont+Additions.h"

@interface PsiCashRewardedVideoButton ()
@end

#pragma mark -

@implementation PsiCashRewardedVideoButton {
    CAGradientLayer* statusGradient;
    UILabel *status;
    UIView *statusGradientLabel;
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

- (void)dealloc {
    [status removeObserver:self forKeyPath:@"bounds"];
}

-(void)setBounds:(CGRect)bounds{
    [super setFrame:bounds];

    [self setRoundedCornersWithBounds:bounds];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    UILabel *label = (UILabel*)object;
    if (label != nil && label == status && [keyPath isEqualToString:@"bounds"]) {
        statusGradient.frame = statusGradientLabel.bounds;
    }
}

- (void)setRoundedCornersWithBounds:(CGRect)bounds {
    UIBezierPath* rounded = [UIBezierPath bezierPathWithRoundedRect:bounds byRoundingCorners:UIRectCornerBottomLeft | UIRectCornerBottomRight cornerRadii:CGSizeMake(5, 5)];
    CAShapeLayer* shape = [[CAShapeLayer alloc] init];
    [shape setPath:rounded.CGPath];
    self.layer.mask = shape;
}

- (void)setupViews {
    self.clipsToBounds = YES;
    self.backgroundColor = [UIColor clearColor];
    self.layer.borderWidth = 2.f;
    self.layer.borderColor = [UIColor colorWithRed:0.94 green:0.96 blue:0.99 alpha:1.0].CGColor;
    self.contentEdgeInsets = UIEdgeInsetsMake(10.0f, 30.0f, 10.0f, 30.0f);

    // Setup status label
    statusGradientLabel = [[UIView alloc] init];
    statusGradientLabel.layer.cornerRadius = 4.f;

    CGFloat cornerRadius = 8.f;

    status = [[UILabel alloc] init];
    status.backgroundColor = [UIColor clearColor];
    status.adjustsFontSizeToFitWidth = YES;
    status.font = [UIFont avenirNextDemiBold:16.f];
    status.textAlignment = NSTextAlignmentCenter;
    status.textColor = [UIColor whiteColor];
    status.userInteractionEnabled = NO;
    status.layer.cornerRadius = cornerRadius;
    status.clipsToBounds = YES;
    status.backgroundColor = [UIColor clearColor];

    statusGradient = [CAGradientLayer layer];
    statusGradient.frame = status.bounds;
    statusGradient.colors = @[(id)UIColor.lightRoyalBlueTwo.CGColor, (id)UIColor.lightishBlue.CGColor];
    statusGradient.cornerRadius = cornerRadius;
    [statusGradientLabel.layer addSublayer:statusGradient];

    [status addObserver:self forKeyPath:@"bounds" options:NSKeyValueObservingOptionNew context:nil];

    // Assume at first that a video has not been loaded
    [self videoReady:NO];
}

- (void)addViews {
    [self addSubview:statusGradientLabel];
    [statusGradientLabel addSubview:status];
}

- (void)setupLayoutConstraints {
    statusGradientLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [statusGradientLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [statusGradientLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:2.f /* don't overlap top border */].active = YES;
    [statusGradientLabel.widthAnchor constraintEqualToAnchor:self.widthAnchor constant:-18.f].active = YES;
    [statusGradientLabel.heightAnchor constraintEqualToAnchor:self.heightAnchor constant:-9.f].active = YES;

    status.translatesAutoresizingMaskIntoConstraints = NO;
    [status.centerXAnchor constraintEqualToAnchor:statusGradientLabel.centerXAnchor].active = YES;
    [status.centerYAnchor constraintEqualToAnchor:statusGradientLabel.centerYAnchor].active = YES;
    [status.widthAnchor constraintEqualToAnchor:statusGradientLabel.widthAnchor constant:-20.f].active = YES;
    [status.heightAnchor constraintEqualToAnchor:statusGradientLabel.heightAnchor constant:0.f].active = YES;
}

- (void)videoReady:(BOOL)ready {
    if (ready) {
        status.text = NSLocalizedStringWithDefaultValue(@"REWARDED_VIDEO_EARN_PSICASH", nil, [NSBundle mainBundle],
                                                        @"Watch a video to earn PsiCash!",
                                                        @"Button label indicating to the user that they will earn PsiCash if they watch a video advertisement."
                                                        " The word 'PsiCash' should not be translated or transliterated.");
        statusGradient.colors = @[(id)UIColor.lightRoyalBlueTwo.CGColor, (id)UIColor.lightishBlue.CGColor];
    } else {
        status.text = NSLocalizedStringWithDefaultValue(@"REWARDED_VIDEO_NO_VIDEOS_AVAILABLE", nil, [NSBundle mainBundle],
                                                        @"No Videos Available",
                                                        @"Button label indicating to the user that there are no videos available for them to watch.");
        statusGradient.colors = @[(id)UIColor.lightBlueGrey.CGColor, (id)UIColor.lightBlueGrey.CGColor];
    }
}

@end
