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


NS_ASSUME_NONNULL_BEGIN

@interface UIView (Additions)

@property(nonatomic, readonly) NSLayoutXAxisAnchor *safeLeadingAnchor;
@property(nonatomic, readonly) NSLayoutXAxisAnchor *safeTrailingAnchor;
@property(nonatomic, readonly) NSLayoutXAxisAnchor *safeLeftAnchor;
@property(nonatomic, readonly) NSLayoutXAxisAnchor *safeRightAnchor;
@property(nonatomic, readonly) NSLayoutYAxisAnchor *safeTopAnchor;
@property(nonatomic, readonly) NSLayoutYAxisAnchor *safeBottomAnchor;
@property(nonatomic, readonly) NSLayoutDimension *safeWidthAnchor;
@property(nonatomic, readonly) NSLayoutDimension *safeHeightAnchor;
@property(nonatomic, readonly) NSLayoutXAxisAnchor *safeCenterXAnchor;
@property(nonatomic, readonly) NSLayoutYAxisAnchor *safeCenterYAnchor;

@end

NS_ASSUME_NONNULL_END
