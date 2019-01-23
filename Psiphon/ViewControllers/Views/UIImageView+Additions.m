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

#import "UIImageView+Additions.h"


@implementation UIImageView (Additions)

- (NSLayoutConstraint *)constraintWidthToImageRatio {
    assert(self.image != nil);
    return [self.widthAnchor constraintEqualToAnchor:self.heightAnchor
                                   multiplier:self.image.size.width / self.image.size.height];
}

- (NSLayoutConstraint *)constraintHeightToImageRatio {
    assert(self.image != nil);
    return [self.heightAnchor constraintEqualToAnchor:self.widthAnchor
                                         multiplier:self.image.size.height / self.image.size.width];
}

@end
