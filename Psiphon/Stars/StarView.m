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

#import "StarView.h"

@implementation StarView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        UIImage *star = [UIImage imageNamed:@"Star"];
        self.image = star;
        self.contentMode = UIViewContentModeScaleAspectFit;
        [self.layer setMinificationFilter:kCAFilterTrilinear];
    }

    return self;
}

- (void)blinkWithPeriod:(CGFloat)period andDelay:(CGFloat)delay andMinAlpha:(CGFloat)minAlpha {
    self.alpha = 1;
    [UIView animateKeyframesWithDuration:period delay:delay options:UIViewKeyframeAnimationOptionCalculationModeLinear | UIViewKeyframeAnimationOptionRepeat animations:^{
        [UIView addKeyframeWithRelativeStartTime:0 relativeDuration:0.5 animations:^{
            self.alpha = minAlpha;
        }];
        [UIView addKeyframeWithRelativeStartTime:0.5 relativeDuration:0.5 animations:^{
            self.alpha = 1;
        }];
    } completion:nil];
}

@end

