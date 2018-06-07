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

#import "PastelView.h"
#import "Pastel.h"

#define AnimationKeyPath @"colors"
#define AnimationKey @"ColorChange"

@implementation PastelView {
    CGPoint startPoint;
    CGPoint endPoint;

    CGPoint startPastelPoint;
    CGPoint endPastelPoint;

    NSTimeInterval animationDuration;

    CAGradientLayer *gradient;

    int currentGradient;
}


- (instancetype)init {
    self = [super init];
    if (self) {
        startPoint = PastelPoint(left);
        endPoint = PastelPoint(right);

        startPastelPoint = PastelPoint(left);
        endPastelPoint = PastelPoint(right);

        animationDuration = 2.0;

        gradient = [CAGradientLayer layer];

        currentGradient = 0;

        _colors = @[

            [UIColor colorWithRed:0.16 green:0.38 blue:1.00 alpha:1.0],
            [UIColor colorWithRed:0.55 green:0.72 blue:1.00 alpha:1.0]
        ];

    }
    return self;
}

- (void)startAnimation {
    [gradient removeAllAnimations];
    [self setup];
    [self animateGradient];
}

- (void)setup {
    gradient.frame = self.bounds;
    gradient.colors = [self currentGradientSet];
    gradient.startPoint = startPoint;
    gradient.endPoint = endPoint;
    gradient.drawsAsynchronously = TRUE;

    [self.layer insertSublayer:gradient atIndex:0];
}

- (NSArray *)currentGradientSet {
    if ([self.colors count] < 1) {
        return @[];
    }

    return @[
      (id)self.colors[currentGradient % [self.colors count]].CGColor,
      (id)self.colors[(currentGradient + 1) % [self.colors count]].CGColor
    ];
}

- (void)animateGradient {
    currentGradient += 1;

    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:AnimationKeyPath];
    animation.duration = animationDuration;
    animation.toValue = [self currentGradientSet];
    animation.fillMode = kCAFillModeForwards;
    [animation setRemovedOnCompletion:FALSE];
    animation.delegate = self;
    [gradient addAnimation:animation forKey:AnimationKey];
}

#pragma mark - UIView overrides

- (void)layoutSubviews {
    [super layoutSubviews];
    gradient.frame = self.bounds;
}

- (void)removeFromSuperview {
    [super removeFromSuperview];
    [gradient removeAllAnimations];
    [gradient removeFromSuperlayer];
}

#pragma mark - CAAnimationDelegate

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag {
    if (flag) {
        gradient.colors = [self currentGradientSet];
        [self animateGradient];
    }
}

@end
