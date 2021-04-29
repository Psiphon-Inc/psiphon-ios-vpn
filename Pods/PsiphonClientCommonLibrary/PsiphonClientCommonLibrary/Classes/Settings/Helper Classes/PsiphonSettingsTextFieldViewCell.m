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


#import "PsiphonSettingsTextFieldViewCell.h"
#import "IASKSettingsReader.h"
#import "IASKTextField.h"

@implementation PsiphonSettingsTextFieldViewCell
- (void)layoutSubviews {
    [super layoutSubviews];

    if([UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionLeftToRight) {
        return;
    }

    //reset text alignment and calculate new frames for RTL
    self.textLabel.textAlignment = NSTextAlignmentLeft;
    self.textField.textAlignment = NSTextAlignmentLeft;

    CGRect frame = [self rtlFrame:self.textField];
    self.textField.frame = frame;

    frame = [self rtlFrame:self.textLabel];
    self.textLabel.frame = frame;
}

-(CGRect) rtlFrame:(UIView *)view {
    CGRect frame = view.frame;
    CGRect superViewFrame = [view superview].frame;

    return CGRectMake(superViewFrame.size.width - frame.origin.x - frame.size.width, frame.origin.y, frame.size.width, frame.size.height);
}

@end
