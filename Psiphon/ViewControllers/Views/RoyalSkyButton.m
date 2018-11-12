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
#import "UIFont+Additions.h"
#import "UIColor+Additions.h"
#import "LayerAutoResizeUIView.h"

@implementation RoyalSkyButton {
    CAGradientLayer* statusGradientLayer;
    LayerAutoResizeUIView *statusGradientView;
    UILabel *titleLabel;

    NSString *normalTitle;
    NSString *disabledTitle;
}

- (void)setTitle:(NSString *)title {
    normalTitle = title;
    disabledTitle = title;
}

- (void)setTitle:(NSString *)title forState:(UIControlState)controlState {
    if (controlState == UIControlStateNormal) {
        normalTitle = title;
    } else if (controlState == UIControlStateDisabled) {
        disabledTitle = title;
    }
}

- (NSString *)currentTitle {
    if (self.enabled) {
        return normalTitle;
    } else {
        return disabledTitle;
    }
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    titleLabel.attributedText = [RoyalSkyButton styleLabelText:self.currentTitle];

    if (enabled) {
        statusGradientLayer.colors = @[(id)UIColor.lightRoyalBlueTwo.CGColor,
                                       (id)UIColor.lightishBlue.CGColor];
    } else {
        statusGradientLayer.colors = @[(id)UIColor.lightBlueGrey.CGColor,
                                       (id)UIColor.lightBlueGrey.CGColor];
    }
}

#pragma mark - Resize events

- (void)layoutSubviews {
    [super layoutSubviews];
    UIBezierPath* rounded = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                    byRoundingCorners:UIRectCornerBottomLeft|UIRectCornerBottomRight
                                          cornerRadii:CGSizeMake(5, 5)];
    CAShapeLayer* shape = [[CAShapeLayer alloc] init];
    [shape setPath:rounded.CGPath];
    self.layer.mask = shape;
}

#pragma mark - AutoLayoutViewGroup

- (void)setupViews {
    self.clipsToBounds = YES;
    self.backgroundColor = [UIColor clearColor];
    self.layer.borderWidth = 2.f;
    self.layer.borderColor = [UIColor colorWithRed:0.94 green:0.96 blue:0.99 alpha:1.0].CGColor;

    statusGradientView = [[LayerAutoResizeUIView alloc] init];
    statusGradientView.layer.cornerRadius = 4.f;

    CGFloat cornerRadius = 8.f;

    titleLabel = [[UILabel alloc] init];
    titleLabel.backgroundColor = [UIColor clearColor];

    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.8;
    titleLabel.font = [UIFont avenirNextDemiBold:16.f];

    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.userInteractionEnabled = NO;
    titleLabel.layer.cornerRadius = cornerRadius;
    titleLabel.clipsToBounds = YES;
    titleLabel.backgroundColor = [UIColor clearColor];

    statusGradientLayer = [CAGradientLayer layer];
    statusGradientLayer.colors = @[(id)UIColor.lightRoyalBlueTwo.CGColor,
                                   (id)UIColor.lightishBlue.CGColor];
    statusGradientLayer.cornerRadius = cornerRadius;
    [statusGradientView addSublayerToMainLayer:statusGradientLayer];
}

- (void)addSubviews {
    [self addSubview:statusGradientView];
    [self addSubview:titleLabel];
}

- (void)setupSubviewsLayoutConstraints {
    statusGradientView.translatesAutoresizingMaskIntoConstraints = NO;
    [statusGradientView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [statusGradientView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                  constant:2.f] /* don't overlap top border */
                                                  .active = TRUE;

    [statusGradientView.widthAnchor constraintEqualToAnchor:self.widthAnchor
                                                    constant:-18.f].active = YES;
    [statusGradientView.heightAnchor constraintEqualToAnchor:self.heightAnchor
                                                     constant:-9.f].active = YES;

    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;

    [titleLabel.centerYAnchor
      constraintEqualToAnchor:statusGradientView.centerYAnchor].active = YES;

    [titleLabel.widthAnchor
      constraintEqualToAnchor:statusGradientView.widthAnchor
                     constant:-20.f].active = TRUE;
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
