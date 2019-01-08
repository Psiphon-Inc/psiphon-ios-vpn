/*
 * Copyright (c) 2019, Psiphon Inc.
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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIImageView (Additions)

/** Create a new layout constraint that constraints view's width to view's height, maintaining
 * the ratio of the image's width to height.
 * @return NSLayoutConstraint that must be activated.
 */
- (NSLayoutConstraint *)constraintWidthToImageRatio;

/** Create a new layout constraint that constraints view's height to view's width, maintaining
 * the ratio of the image's height to width.
 * @return NSLayoutConstraint that must be activated.
 */
- (NSLayoutConstraint *)constraintHeightToImageRatio;

@end

NS_ASSUME_NONNULL_END
