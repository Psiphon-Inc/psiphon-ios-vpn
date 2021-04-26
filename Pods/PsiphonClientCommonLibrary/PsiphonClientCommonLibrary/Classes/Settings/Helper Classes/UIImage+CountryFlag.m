/*
 * Copyright (c) 2017, Psiphon Inc.
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

#import "UIImage+CountryFlag.h"

@implementation UIImage (UIImageCountryFlag)

- (UIImage *)countryFlag {
    CGFloat blur = 2;
    UIColor* shadowColor = [UIColor colorWithWhite:0 alpha:0.25];
    CGSize offset = CGSizeMake(1, 1);

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(self.size.width + 2 * blur, self.size.height + 2 * blur), NO, 0);

    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextSetShadowWithColor(context, offset, blur, shadowColor.CGColor);

    [self drawInRect:CGRectMake(blur - offset.width / 2, blur - offset.height / 2, self.size.width, self.size.height)];

    UIImage* flag = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();

    return flag;
}

@end
