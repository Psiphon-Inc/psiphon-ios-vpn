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
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.titleLabel.attributedText = [RoyalSkyButton styleLabelText:self.currentTitle];

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
    self.contentEdgeInsets = UIEdgeInsetsMake(10.0f, 30.0f, 10.0f, 30.0f);

    statusGradientView = [[LayerAutoResizeUIView alloc] init];
    statusGradientView.layer.cornerRadius = 4.f;

    CGFloat cornerRadius = 8.f;

    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.font = [UIFont avenirNextDemiBold:16.f];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.userInteractionEnabled = NO;
    self.titleLabel.layer.cornerRadius = cornerRadius;
    self.titleLabel.clipsToBounds = YES;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.minimumScaleFactor = 0.8;

    statusGradientLayer = [CAGradientLayer layer];
    statusGradientLayer.colors = @[(id)UIColor.lightRoyalBlueTwo.CGColor,
                                   (id)UIColor.lightishBlue.CGColor];
    statusGradientLayer.cornerRadius = cornerRadius;
    [statusGradientView addSublayerToMainLayer:statusGradientLayer];
}

- (void)addSubviews {
    [self insertSubview:statusGradientView belowSubview:self.titleLabel];
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

    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.titleLabel.centerXAnchor constraintEqualToAnchor:statusGradientView.centerXAnchor]
      .active = YES;
    [self.titleLabel.centerYAnchor constraintEqualToAnchor:statusGradientView.centerYAnchor]
      .active = YES;

    [self.titleLabel.widthAnchor constraintEqualToAnchor:statusGradientView.widthAnchor
                                       constant:-20.f].active = TRUE;
    [self.titleLabel.heightAnchor constraintEqualToAnchor:statusGradientView.heightAnchor
                                        constant:0.f].active = TRUE;
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
