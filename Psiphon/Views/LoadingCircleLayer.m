/*
 * Copyright (c) 2017, Psiphon Inc. Created by Draven Johnson on 2017-08-30.
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

#import "LoadingCircleLayer.h"

// Starting angle in radians
#define kLoadingCircleStartAngle -M_PI_2

@implementation LoadingCircleLayer

// Animated properties must be dynamic
@dynamic progress;
@dynamic circleRadius;
@dynamic circleRadiusRatio;
@dynamic drawClockwise;
@dynamic lineWidth;
@dynamic lineColor;

- (id)init {
    self = [super init];

    if (self) {
        // Setup defaults
        self.progress = 0;
        self.circleRadius = 0;
        self.circleRadiusRatio = 1;
        self.drawClockwise = YES;
        self.lineWidth = 1;
        self.lineColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
        self.updateDuration = 1;
    }

    return self;
}

+ (BOOL)needsDisplayForKey:(NSString *)key {
    // Returning true for a given property causes the layer's contents to
    // be redrawn when the property is changed.
    // See https://developer.apple.com/documentation/quartzcore/calayer/1410769-needsdisplay.
    if ([@"progress" isEqualToString:key])
    {
        return YES;
    }
    return [super needsDisplayForKey:key];
}

- (id<CAAction>)actionForKey:(NSString *)key {
    // Returns the action object associated with the event named by the
    // string 'event'.
    // See https://developer.apple.com/documentation/quartzcore/calayer/1410844-action.
    if ([key isEqualToString:@"progress"])
    {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:key];
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        animation.fromValue = @(self.progress);
        animation.duration = self.updateDuration;
        return animation;
    }
    return [super actionForKey:key];
}

-(void)drawInContext:(CGContextRef)ctx {
    CGRect rect = self.bounds;

    // Clear previous drawings
    CGContextClearRect(ctx, rect);

    // Define circle
    CGContextAddArc(ctx, CGRectGetMidX(rect), CGRectGetMidY(rect), [self getLoadingCircleRadius], kLoadingCircleStartAngle, (2.f * M_PI * self.progress) + kLoadingCircleStartAngle, !self.drawClockwise);
    CGContextSetLineWidth(ctx, self.lineWidth);

    // Set the render colors.
    CGContextSetFillColorWithColor(ctx, [UIColor clearColor].CGColor);
    CGContextSetStrokeColorWithColor(ctx, self.lineColor);

    // Draw
    CGContextStrokePath(ctx);
}

#pragma mark - helpers

- (CGFloat)getLoadingCircleRadius {
    CGFloat radius = 0;

    // If set circle radius takes precedence over circleRadiusRatio
    if (self.circleRadius > 0) {
        radius = self.circleRadius;
    } else {
        radius = ([self minDimensionLength] / 2) * self.circleRadiusRatio;
    }

    return radius - self.lineWidth;
}

- (CGSize)size {
    CGFloat ratioOfMinDimension = 1.f;
    CGFloat len = ratioOfMinDimension * [self minDimensionLength];
    return CGSizeMake(len, len);
}

- (CGFloat)minDimensionLength {
    return MIN(self.frame.size.width, self.frame.size.height);
}

@end
