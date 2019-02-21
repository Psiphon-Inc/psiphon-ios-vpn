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
    UIImageView *_Nullable chevron;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _includeChevron = FALSE;
        self.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    }
    return self;
}

- (void)setIncludeChevron:(BOOL)includeChevron {
    _includeChevron = includeChevron;
    if (includeChevron) {
        self.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    } else {
        self.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    }
    [self setNeedsUpdateConstraints];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (self.includeChevron && !chevron) {
        chevron = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ChevronBlue"]];
        [self addSubview:chevron];

        chevron.translatesAutoresizingMaskIntoConstraints = FALSE;
        [chevron.centerYAnchor constraintEqualToAnchor:self.centerYAnchor
                                              constant:2.f].active = TRUE;
        [chevron.trailingAnchor
          constraintEqualToAnchor:self.trailingAnchor
                         constant:-25.f].active = TRUE;
    }
}

- (void)autoLayoutSetupViews {
    [super autoLayoutSetupViews];

    self.backgroundColor = UIColor.whiteColor;
    self.titleLabel.textColor = UIColor.lightishBlue;

    self.layer.borderWidth = 1.5f;
    self.layer.borderColor = UIColor.periwinkleColor.CGColor;
}

@end
