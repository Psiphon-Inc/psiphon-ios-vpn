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

#import "RingSkyButton.h"
#import "UIColor+Additions.h"

@implementation RingSkyButton {
    UIImageView *chevron;
}

- (void)autoLayoutSetupViews {
    [super autoLayoutSetupViews];

    self.backgroundColor = UIColor.whiteColor;
    self.shadow = TRUE;
    self.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;

    self.layer.borderWidth = 1.5f;
    self.layer.borderColor = UIColor.periwinkleColor.CGColor;

    chevron = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"chevron"]];
}

- (void)autoLayoutAddSubviews {
    [super autoLayoutAddSubviews];
    [self addSubview:chevron];
}

- (void)autoLayoutSetupSubviewsLayoutConstraints {
    [super autoLayoutSetupSubviewsLayoutConstraints];

    chevron.translatesAutoresizingMaskIntoConstraints = FALSE;
    [chevron.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:2.f].active = TRUE;
    [chevron.trailingAnchor
      constraintEqualToAnchor:self.trailingAnchor
                     constant:-25.f].active = TRUE;
}

@end
