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

#import "ArrowView.h"
#import "UIColor+Additions.h"


@implementation ArrowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
    }
    return self;
}


- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();

    // Drawing path
    //
    //     1
    //    /  \
    //   /    \
    //  7-6  3-2  <-- triangleHeight
    //    |  |
    //    |  |
    //    5--4
    //       |-|  <-- baseWidth

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    CGFloat triangleHeight = 0.25f * height;
    CGFloat baseWidth = 0.36f * width;

    UIBezierPath *fillPath = [UIBezierPath bezierPath];
    [fillPath moveToPoint:CGPointMake(width/2, 0)]; // 1
    [fillPath addLineToPoint:CGPointMake(width, triangleHeight)]; // 2
    [fillPath addLineToPoint:CGPointMake(width - baseWidth, triangleHeight)]; // 3
    [fillPath addLineToPoint:CGPointMake(width - baseWidth, height)]; // 4
    [fillPath addLineToPoint:CGPointMake(baseWidth, height)]; // 5
    [fillPath addLineToPoint:CGPointMake(baseWidth, triangleHeight)]; // 6
    [fillPath addLineToPoint:CGPointMake(0, triangleHeight)]; // 7
    [fillPath closePath];

    CGContextAddPath(context, fillPath.CGPath);
    CGContextSetFillColorWithColor(context, UIColor.peachyPink.CGColor);
    CGContextFillPath(context);
}

@end
