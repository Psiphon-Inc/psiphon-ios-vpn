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
#import "RoyalSkyButton.h"
#import "UIColor+Additions.h"
#import "LayerAutoResizeUIView.h"

@implementation RoyalSkyButton {
    CAGradientLayer* statusGradientLayer;
    LayerAutoResizeUIView *statusGradientView;
}

- (void)setBackgroundGradient:(BOOL)enableGradient {

    if (enableGradient) {
        statusGradientLayer.colors = @[(id)UIColor.lightRoyalBlueTwo.CGColor,
                                       (id)UIColor.lightishBlue.CGColor];
    } else {
        statusGradientLayer.colors = @[(id)UIColor.regentGrey.CGColor,
                                       (id)UIColor.regentGrey.CGColor];
    }
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];

    // TODO: Each View class should have a state mutating method.
    //       Take this out once `-setState` methods are implemented.
    [self setBackgroundGradient:enabled];
}

#pragma mark - AutoLayoutViewGroup

- (void)autoLayoutSetupViews {
    [super autoLayoutSetupViews];
    statusGradientView = [[LayerAutoResizeUIView alloc] init];
    statusGradientView.userInteractionEnabled = FALSE;  // Pass events through to parent view.
    statusGradientView.layer.cornerRadius = 4.f;

    CGFloat cornerRadius = 8.f;

    statusGradientLayer = [CAGradientLayer layer];
    statusGradientLayer.colors = @[(id)UIColor.lightRoyalBlueTwo.CGColor,
                                   (id)UIColor.lightishBlue.CGColor];
    statusGradientLayer.cornerRadius = cornerRadius;
    [statusGradientView addSublayerToMainLayer:statusGradientLayer];
}

- (void)autoLayoutAddSubviews {
    [super autoLayoutAddSubviews];
    [self insertSubview:statusGradientView belowSubview:self.titleLabel];
}

- (void)autoLayoutSetupSubviewsLayoutConstraints {
    [super autoLayoutSetupSubviewsLayoutConstraints];
    statusGradientView.translatesAutoresizingMaskIntoConstraints = NO;
    [statusGradientView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;

    [statusGradientView.topAnchor constraintEqualToAnchor:self.topAnchor].active = TRUE;

    [statusGradientView.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
    [statusGradientView.heightAnchor constraintEqualToAnchor:self.heightAnchor].active = YES;
}

#pragma mark - helper methods

+ (NSAttributedString*)styleLabelText:(NSString*)s {
    NSMutableAttributedString *mutableStr = [[NSMutableAttributedString alloc] initWithString:s];
    [mutableStr addAttribute:NSKernAttributeName
                       value:@-0.2
                       range:NSMakeRange(0, mutableStr.length)];
    return mutableStr;
}

@end
