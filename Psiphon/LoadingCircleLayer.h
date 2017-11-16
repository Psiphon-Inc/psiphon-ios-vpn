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

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

@interface LoadingCircleLayer : CALayer

/* Percent complete in the range [0, 1]. */

@property (nonatomic) CGFloat progress;

/* If set property takes precedence over `circleRadiusRatio`. */

@property (nonatomic) CGFloat circleRadius;

/* Set circle radius to a percentage of LoadingCircleLayer's bounds.
 * That is:
 * radius = (MIN(layer.width, layer.height) / 2) * circleRadiusRation
 * in pseudocode. This will not update the circleRadius property. */

@property (nonatomic) CGFloat circleRadiusRatio;

@property (nonatomic) BOOL drawClockwise;

@property (nonatomic) CGFloat lineWidth;

@property (nonatomic) CGColorRef lineColor;

@property (nonatomic) NSTimeInterval updateDuration;

@end
