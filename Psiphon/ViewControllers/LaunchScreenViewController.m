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
#import "UIFont+Additions.h"


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

    // Background

    UIView *launchScreenView = [[[NSBundle mainBundle] loadNibNamed:@"LaunchScreen" owner:self options:nil] objectAtIndex:0];
    [self.view addSubview:launchScreenView];

    launchScreenView.translatesAutoresizingMaskIntoConstraints = NO;
    [launchScreenView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [launchScreenView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [launchScreenView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [launchScreenView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;

    // Loading label

    loadingLabel = [[UILabel alloc] init];
    loadingLabel.translatesAutoresizingMaskIntoConstraints = NO;

    loadingLabel.adjustsFontSizeToFitWidth = YES;
    loadingLabel.text = NSLocalizedStringWithDefaultValue(@"LOADING", nil, [NSBundle mainBundle], @"Loading...", @"Text displayed while app loads");
    loadingLabel.textAlignment = NSTextAlignmentCenter;
    loadingLabel.textColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    loadingLabel.font = [UIFont avenirNextMedium:20.f];

    [self.view addSubview:loadingLabel];
    [loadingLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    [loadingLabel.centerYAnchor constraintEqualToAnchor:self.bottomLayoutGuide.bottomAnchor constant:-50].active = YES;

    [self setNeedsStatusBarAppearanceUpdate];
}

#pragma mark - helpers

- (CGFloat)minDimensionLength {
    return MIN(self.view.frame.size.width, self.view.frame.size.height);
}

@end
