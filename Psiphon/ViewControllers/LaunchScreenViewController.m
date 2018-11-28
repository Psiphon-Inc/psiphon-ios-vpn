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

#import <Foundation/Foundation.h>
#import "AppDelegate.h"
#import "LaunchScreenViewController.h"
#import "PsiphonProgressView.h"
#import "UIView+AutoLayoutViewGroup.h"


#define kProgressViewToScreenRatio 0.9f
#define kProgressViewMaxDimensionLength 500.f

@implementation LaunchScreenViewController {
    // Loading Text
    UILabel *loadingLabel;

    // Loading Animation
    PsiphonProgressView *progressView;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Lifecycle Methods

- (void)viewDidLoad {
    [super viewDidLoad];

    // Adds background blur effect.
    self.view.backgroundColor = [UIColor clearColor];
    UIBlurEffect *bgBlurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *bgBlurEffectView = [[UIVisualEffectView alloc] initWithEffect:bgBlurEffect];
    bgBlurEffectView.frame = self.view.bounds;
    bgBlurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:bgBlurEffectView];

    [self addProgressView];
    [self addLoadingLabel];

    [self setNeedsStatusBarAppearanceUpdate];
}

#pragma mark - helpers

- (void)addProgressView {
    progressView = [[PsiphonProgressView alloc] initWithAutoLayout];
    progressView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:progressView];

    [progressView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    NSLayoutConstraint *centerYAnchor = [progressView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor];
    // Allow constraint to be broken
    centerYAnchor.priority = UILayoutPriorityDefaultHigh;
    centerYAnchor.active = YES;

    CGFloat len = kProgressViewToScreenRatio * [self minDimensionLength];
    if (len > kProgressViewMaxDimensionLength) {
        len = kProgressViewMaxDimensionLength;
    }
    [progressView.widthAnchor constraintEqualToConstant:len].active = TRUE;
    [progressView.heightAnchor constraintEqualToConstant:len].active = TRUE;
}

- (void)addLoadingLabel {
    loadingLabel = [[UILabel alloc] init];
    loadingLabel.translatesAutoresizingMaskIntoConstraints = NO;

    loadingLabel.adjustsFontSizeToFitWidth = YES;
    loadingLabel.text = NSLocalizedStringWithDefaultValue(@"LOADING", nil, [NSBundle mainBundle], @"Loading...", @"Text displayed while app loads");
    loadingLabel.textAlignment = NSTextAlignmentCenter;
    loadingLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    loadingLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightThin];

    [self.view addSubview:loadingLabel];
    [loadingLabel.heightAnchor constraintEqualToConstant:30.f].active = YES;
    [loadingLabel.widthAnchor constraintEqualToAnchor:progressView.widthAnchor].active = YES;
    [loadingLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    [loadingLabel.topAnchor constraintGreaterThanOrEqualToAnchor:progressView.bottomAnchor].active = YES;
    [loadingLabel.bottomAnchor constraintEqualToAnchor:self.bottomLayoutGuide.bottomAnchor constant:-15].active = YES;
}

- (CGFloat)minDimensionLength {
    return MIN(self.view.frame.size.width, self.view.frame.size.height);
}

@end
