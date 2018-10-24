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

#import "SwoopView.h"


@implementation SwoopView {
    CGFloat fillRatio;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        _directionUp = TRUE;
        fillRatio = 0.24;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGRect bounds = self.bounds;
    CGFloat centerX = bounds.size.width / 2.f;
    CGFloat boxTopY = bounds.size.height * fillRatio;

    CGContextRef c = UIGraphicsGetCurrentContext();

    if (!self.directionUp) {
        // Context rotation is around the origin of the context,
        // we need to translate to center, and then translate back.
        CGContextSaveGState(c);
        CGContextTranslateCTM(c, bounds.size.width, bounds.size.height);
        CGContextRotateCTM(c, M_PI);
    }

    CGContextSetLineWidth(c, 0.f);

    CGContextBeginPath(c);
    CGContextMoveToPoint(c, bounds.origin.x, bounds.size.height); //  bottom-left
    CGContextAddLineToPoint(c, bounds.origin.x, boxTopY);
    CGFloat cpx = centerX;
    CGFloat cpy = bounds.origin.y - boxTopY;
    CGContextAddQuadCurveToPoint(c, cpx, cpy, bounds.size.width, boxTopY); //  end arc at bottom-right
    CGContextAddLineToPoint(c, bounds.size.width, bounds.size.height);
    CGContextAddLineToPoint(c, bounds.origin.x, bounds.size.height);
    CGContextClosePath(c);

    [self.color setFill];
    CGContextDrawPath(c, kCGPathFillStroke);

    if (!self.directionUp) {
        CGContextRestoreGState(c);
    }

}

@end
