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

#import "UIColor+Additions.h"

@implementation UIColor (Additions)

+ (UIColor * _Nonnull)paleBlueColor {
    return [UIColor colorWithRed:244.0f / 255.0f green:250.0f / 255.0f blue:254.0f / 255.0f alpha:1.0f];
}

+ (UIColor * _Nonnull)clearBlueColor {
    return [UIColor colorWithRed:41.0f / 255.0f green:98.0f / 255.0f blue:1.0f alpha:1.0f];
}

+ (UIColor * _Nonnull)clearBlue50Color {
    return [UIColor colorWithRed:41.0f / 255.0f green:98.0f / 255.0f blue:1.0f alpha:0.5f];
}

+ (UIColor * _Nonnull)charcoalGreyColor {
    return [UIColor colorWithRed:60.0f / 255.0f green:66.0f / 255.0f blue:84.0f / 255.0f alpha:1.0f];
}

+ (UIColor * _Nonnull)weirdGreenColor {
    return [UIColor colorWithRed:39.0f / 255.0f green:230.0f / 255.0f blue:131.0f / 255.0f alpha:1.0f];
}

+ (UIColor * _Nonnull)purpleButtonColor {
    return [UIColor colorWithRed:119.0f / 255.0f green:97.0f / 255.0f blue:1.0f alpha:1.0f];
}

@end
