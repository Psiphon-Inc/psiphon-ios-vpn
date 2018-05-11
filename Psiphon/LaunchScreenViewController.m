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
#import "Logging.h"
#import "PsiphonProgressView.h"
#import "PureLayout.h"
#import "RootContainerController.h"

#if DEBUG
#define kLaunchScreenTimerCount 1.f
#else
#define kLaunchScreenTimerCount 10.f
#endif

#define kTimerInterval 1.f

#define kProgressViewToScreenRatio 0.9f
#define kProgressViewMaxDimensionLength 500.f


@interface LaunchScreenViewController ()

@end

static const NSString *ItemStatusContext;

@implementation LaunchScreenViewController {
    // Loading Text
    UILabel *loadingLabel;

    // Loading Timer
    NSTimer *loadingTimer;
    CGFloat timerCount;

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

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // Reset the timer count.
    timerCount = 0.f;

    loadingTimer = [NSTimer scheduledTimerWithTimeInterval:kTimerInterval repeats:TRUE block:^(NSTimer *timer) {
        timerCount += kTimerInterval;
        [progressView setProgress:timerCount / kLaunchScreenTimerCount];
        if (timerCount >= kLaunchScreenTimerCount + kTimerInterval) {
            [timer invalidate];
            [[AppDelegate sharedAppDelegate] launchScreenFinished];
        }
    }];
    [loadingTimer fire];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Stops the timer and removes it from the run loop.
    [loadingTimer invalidate];
}

- (void)willMoveToParentViewController:(nullable UIViewController *)parent {
    [super willMoveToParentViewController:parent];

    if (parent == nil) {
        // no more parenting.
    }
}

#pragma mark - helpers

- (void)addProgressView {
    progressView = [[PsiphonProgressView alloc] init];
    progressView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:progressView];

    [progressView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    NSLayoutConstraint *centerYAnchor = [progressView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor];
    // Allow constraint to be broken
    centerYAnchor.priority = UILayoutPriorityDefaultHigh;
    centerYAnchor.active = YES;

    [progressView autoSetDimensionsToSize:[self progressViewSize]];
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

- (CGSize)progressViewSize {
    CGFloat len = kProgressViewToScreenRatio * [self minDimensionLength];
    if (len > kProgressViewMaxDimensionLength) {
        len = kProgressViewMaxDimensionLength;
    }
    return CGSizeMake(len, len);
}

- (CGFloat)minDimensionLength {
    return MIN(self.view.frame.size.width, self.view.frame.size.height);
}

@end
