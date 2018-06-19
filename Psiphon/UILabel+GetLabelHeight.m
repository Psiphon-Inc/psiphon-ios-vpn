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

#import "UILabel+GetLabelHeight.h"

@implementation UILabel (GetLabelHeight)

// From https://stackoverflow.com/questions/27374612/how-do-i-calculate-the-uilabel-height-dynamically
- (CGFloat)getLabelHeight {
    CGSize constraint = CGSizeMake(self.frame.size.width, CGFLOAT_MAX);
    CGSize size;

    NSStringDrawingContext *context = [[NSStringDrawingContext alloc] init];
    CGSize boundingBox = [self.text boundingRectWithSize:constraint
                                                  options:NSStringDrawingUsesLineFragmentOrigin
                                               attributes:@{NSFontAttributeName:self.font}
                                                  context:context].size;

    size = CGSizeMake(ceil(boundingBox.width), ceil(boundingBox.height));

    return size.height;
}

@end
