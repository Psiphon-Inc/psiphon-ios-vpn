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

#import <UIKit/UIKit.h>
#import "ImageUtils.h"


@implementation ImageUtils

+ (UIImage *)highlightImageWithRoundedCorners:(UIImage *)image {

    // Make the corners rounded.
    CGRect rect = CGRectMake(0.f, 0.f, image.size.width, image.size.height);

    UIGraphicsBeginImageContextWithOptions(image.size, FALSE, 0.f);
    UIBezierPath *roundedPath = [UIBezierPath bezierPathWithRoundedRect:rect
                                                           cornerRadius:3.f];
    [roundedPath addClip];
    [image drawInRect:rect];
    UIImage *roundedImage = UIGraphicsGetImageFromCurrentImageContext();

    // Increase brightness of the image.
    CIImage *ciImage = [[CIImage alloc] initWithImage:roundedImage];
    NSDictionary *params = @{ kCIInputBrightnessKey: @(0.1f),
                              kCIInputSaturationKey: @(1.5f) };

    ciImage = [ciImage imageByApplyingFilter:@"CIColorControls" withInputParameters:params];

    return [[UIImage alloc] initWithCIImage:ciImage
                                      scale:[UIScreen mainScreen].scale
                                orientation:UIImageOrientationUp];
}

@end
