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

#import "CloudsView.h"
#import "UIImageView+Additions.h"


CGFloat const SmallCloudMult = 0.07f;
CGFloat const LargeCloudMult = 0.1f;

@implementation CloudsView {
    NSMutableArray<NSLayoutConstraint *> *dynamicConstraints;

    UIImageView *cloudTopLeft;
    UIImageView *cloudTopRight;
    UIImageView *cloudMiddleLeft;
    UIImageView *cloudBottomLeft;
    UIImageView *cloudBottomRight;
}

- (instancetype)initForAutoLayout {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        dynamicConstraints = [NSMutableArray arrayWithCapacity:9];

        UIImage *largeCloud = [UIImage imageNamed:@"LargeCloud"];
        UIImage *smallCloud = [UIImage imageNamed:@"SmallCloud"];
        UIImage *largeCloudMirrored = [UIImage imageWithCGImage:largeCloud.CGImage
                                                          scale:largeCloud.scale
                                              orientation:UIImageOrientationUpMirrored];
        UIImage *smallCloudMirrored = [UIImage imageWithCGImage:smallCloud.CGImage
                                                          scale:smallCloud.scale
                                              orientation:UIImageOrientationUpMirrored];
        
        cloudTopLeft = [[UIImageView alloc] initWithImage:largeCloudMirrored];
        cloudTopRight= [[UIImageView alloc] initWithImage:largeCloudMirrored];
        cloudMiddleLeft = [[UIImageView alloc] initWithImage:smallCloudMirrored];
        cloudBottomLeft = [[UIImageView alloc] initWithImage:smallCloud];
        cloudBottomRight = [[UIImageView alloc] initWithImage:largeCloud];

        self.translatesAutoresizingMaskIntoConstraints = FALSE;
        [self autoLayoutSetupViews];
        [self autoLayoutAddSubviews];
        [self autoLayoutSetupSubviewsLayoutConstraints];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;

    // Calculating layout constraint constants based on parent's view new width and height.
    // Check autoLayoutAddSubviews to see which index corresponds to which layout constraint.
    dynamicConstraints[0].constant = 0.f;
    dynamicConstraints[1].constant = 0.f;
    dynamicConstraints[2].constant = 0.55f * width;
    dynamicConstraints[3].constant = 0.421f * height;
    dynamicConstraints[4].constant = -0.79f * width;
    dynamicConstraints[5].constant = 0.867f * height;
    dynamicConstraints[6].constant = 0.05f * width;
    dynamicConstraints[7].constant = 0.78f * height;
    dynamicConstraints[8].constant = 0.58f * width;
}

#pragma mark - AutoLayoutProtocol

- (void)autoLayoutSetupViews {}

- (void)autoLayoutAddSubviews {
    [self addSubview:cloudTopLeft];
    [self addSubview:cloudTopRight];
    [self addSubview:cloudMiddleLeft];
    [self addSubview:cloudBottomLeft];
    [self addSubview:cloudBottomRight];
}

- (void)autoLayoutSetupSubviewsLayoutConstraints {

    // Top Left Cloud
    cloudTopLeft.translatesAutoresizingMaskIntoConstraints = FALSE;

    dynamicConstraints[0] = [cloudTopLeft.topAnchor constraintEqualToAnchor:self.topAnchor];

    [NSLayoutConstraint activateConstraints:@[
      [cloudTopLeft.heightAnchor constraintEqualToAnchor:self.heightAnchor
                                              multiplier:LargeCloudMult],

      [cloudTopLeft constraintWidthToImageRatio],

      [cloudTopLeft.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:-170.f]
    ]];

    // Top Right Cloud
    cloudTopRight.translatesAutoresizingMaskIntoConstraints = FALSE;

    dynamicConstraints[1] = [cloudTopRight.topAnchor constraintEqualToAnchor:self.topAnchor];
    dynamicConstraints[2] = [cloudTopRight.leadingAnchor constraintEqualToAnchor:self.leadingAnchor];

    [NSLayoutConstraint activateConstraints:@[
      [cloudTopRight.heightAnchor constraintEqualToAnchor:self.heightAnchor
                                              multiplier:LargeCloudMult],

      [cloudTopRight constraintWidthToImageRatio]
    ]];

    // Middle Left Cloud
    cloudMiddleLeft.translatesAutoresizingMaskIntoConstraints = FALSE;

    dynamicConstraints[3] = [cloudMiddleLeft.topAnchor constraintEqualToAnchor:self.topAnchor];
    dynamicConstraints[4] = [cloudMiddleLeft.trailingAnchor
      constraintEqualToAnchor:self.trailingAnchor];

    [NSLayoutConstraint activateConstraints:@[
      [cloudMiddleLeft.heightAnchor constraintEqualToAnchor:self.heightAnchor
                                                 multiplier:LargeCloudMult],

      [cloudMiddleLeft constraintWidthToImageRatio]
    ]];


    // Bottom Left Cloud
    cloudBottomLeft.translatesAutoresizingMaskIntoConstraints = FALSE;

    dynamicConstraints[5] = [cloudBottomLeft.topAnchor constraintEqualToAnchor:self.topAnchor];
    dynamicConstraints[6] = [cloudBottomLeft.leadingAnchor
      constraintEqualToAnchor:self.leadingAnchor];

    [NSLayoutConstraint activateConstraints:@[
      [cloudBottomLeft.heightAnchor constraintEqualToAnchor:self.heightAnchor
                                                 multiplier:SmallCloudMult],

      [cloudBottomLeft constraintWidthToImageRatio]
    ]];

    // Bottom Right Cloud
    cloudBottomRight.translatesAutoresizingMaskIntoConstraints = FALSE;

    dynamicConstraints[7] = [cloudBottomRight.topAnchor constraintEqualToAnchor:self.topAnchor];
    dynamicConstraints[8] = [cloudBottomRight.leadingAnchor
      constraintEqualToAnchor:self.leadingAnchor];

    [NSLayoutConstraint activateConstraints:@[
      [cloudBottomRight.heightAnchor constraintEqualToAnchor:self.heightAnchor
                                                  multiplier:LargeCloudMult],

      [cloudBottomRight constraintWidthToImageRatio]
    ]];

    // Also activate the dynamic constraints
    [NSLayoutConstraint activateConstraints:dynamicConstraints];
}

@end
