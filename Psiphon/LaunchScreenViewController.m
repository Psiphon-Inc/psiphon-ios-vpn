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
#import "LaunchScreenViewController.h"
#import "Logging.h"
#import "RootContainerController.h"
#import "AppDelegate.h"

#if DEBUG
#define kLaunchScreenTimerCount 1.f
#else
#define kLaunchScreenTimerCount 10.f
#endif

#define kTimerInterval 1.f

#define kLogoToScreenRatio 0.69f

@interface LaunchScreenViewController ()

@property (strong, nonatomic) UIProgressView *progressView;

@end

static const NSString *ItemStatusContext;

@implementation LaunchScreenViewController {
    // Loading Text
    UILabel *loadingLabel;

    // Loading Timer
    NSTimer *loadingTimer;
    float timerCount;

    NSLayoutConstraint *logoScreenWidth;
    NSLayoutConstraint *logoScreenHeight;
    NSLayoutConstraint *logoWidth;
}

- (id)init {
    self = [super init];
    return self;
}

- (void)dealloc {
}


#pragma mark - Lifecycle Methods

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {

    [self.view removeConstraint:logoWidth];

    if (size.width > size.height) {
        [self.view removeConstraint:logoScreenWidth];
        [self.view addConstraint:logoScreenHeight];
    } else {
        [self.view removeConstraint:logoScreenHeight];
        [self.view addConstraint:logoScreenWidth];
    }

    [self.view addConstraint:logoWidth];

    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    }];

    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Adds background blur effect.
    self.view.backgroundColor = [UIColor clearColor];
    UIBlurEffect *bgBlurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *bgBlurEffectView = [[UIVisualEffectView alloc] initWithEffect:bgBlurEffect];
    bgBlurEffectView.frame = self.view.bounds;
    bgBlurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [self.view addSubview:bgBlurEffectView];

    [self addLoadingLabel];
    [self addProgressView];
    [self addPsiphonLogo];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];


    // Reset the timer count.
    timerCount = 1.f;
    [self.progressView setProgress:timerCount / kLaunchScreenTimerCount animated:TRUE];

    loadingTimer = [NSTimer scheduledTimerWithTimeInterval:kTimerInterval repeats:TRUE block:^(NSTimer *timer) {
        timerCount += kTimerInterval;
        [self.progressView setProgress:(timerCount / kLaunchScreenTimerCount) animated:TRUE];
        if (timerCount >= kLaunchScreenTimerCount + kTimerInterval) {
            [timer invalidate];

            [[AppDelegate sharedAppDelegate] launchScreenFinished];
        }
    }];
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

#pragma mark -

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)addLoadingLabel {
    loadingLabel = [[UILabel alloc] init];
    loadingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    loadingLabel.adjustsFontSizeToFitWidth = YES;
    loadingLabel.text = NSLocalizedStringWithDefaultValue(@"LOADING", nil, [NSBundle mainBundle], @"Loading...", @"Text displayed while app loads");
    loadingLabel.textAlignment = NSTextAlignmentCenter;
    loadingLabel.textColor = [UIColor whiteColor];

    [self.view addSubview:loadingLabel];

    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:loadingLabel
                                                          attribute:NSLayoutAttributeHeight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:nil
                                                          attribute:NSLayoutAttributeNotAnAttribute
                                                         multiplier:1.0
                                                           constant:30.f]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:loadingLabel
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:-30.f]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:loadingLabel
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:-30.f]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:loadingLabel
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.0
                                                           constant:30]];
}

- (void)addProgressView {
    self.progressView = [[UIProgressView alloc] init];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressView.tintColor = [[UIColor redColor] colorWithAlphaComponent:1.0];

    [self.view addSubview:self.progressView];

    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.progressView
                                                          attribute:NSLayoutAttributeHeight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:nil
                                                          attribute:NSLayoutAttributeNotAnAttribute
                                                         multiplier:1.0
                                                           constant:2]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.progressView
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:loadingLabel
                                                          attribute:NSLayoutAttributeTop
                                                         multiplier:1.0
                                                           constant:-15.f]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.progressView
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.0
                                                           constant:15.0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.progressView
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:-15.f]];
}

- (void)addPsiphonLogo {
    UIImage *logoImage = [UIImage imageNamed:@"LaunchScreen"];
    UIImageView *logoView = [[UIImageView alloc] initWithImage:logoImage];
    logoView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:logoView];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:logoView
                                                          attribute:NSLayoutAttributeCenterX
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeCenterX
                                                         multiplier:1.0
                                                           constant:0.0]];

    NSLayoutConstraint *centerYConstraint = [NSLayoutConstraint constraintWithItem:logoView
                                                          attribute:NSLayoutAttributeCenterY
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeCenterY
                                                         multiplier:1.0
                                                           constant:0.0];

    centerYConstraint.priority = 999;
    [self.view addConstraint:centerYConstraint];

    logoScreenWidth = [NSLayoutConstraint constraintWithItem:logoView
                                                   attribute:NSLayoutAttributeWidth
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:self.view
                                                   attribute:NSLayoutAttributeWidth
                                                  multiplier:kLogoToScreenRatio
                                                    constant:0];

    logoScreenHeight = [NSLayoutConstraint constraintWithItem:logoView
                                                    attribute:NSLayoutAttributeHeight
                                                    relatedBy:NSLayoutRelationEqual
                                                       toItem:self.view
                                                    attribute:NSLayoutAttributeHeight
                                                   multiplier:kLogoToScreenRatio
                                                     constant:0];

    logoWidth = [NSLayoutConstraint constraintWithItem:logoView
                                             attribute:NSLayoutAttributeHeight
                                             relatedBy:NSLayoutRelationEqual
                                                toItem:logoView
                                             attribute:NSLayoutAttributeWidth
                                            multiplier:1.0
                                              constant:0];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.progressView
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                             toItem:logoView
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:10.0]];

    CGSize viewSize = self.view.bounds.size;

    if (viewSize.width > viewSize.height) {
        [self.view addConstraint:logoScreenHeight];
    } else {
        [self.view addConstraint:logoScreenWidth];
    }

    [self.view addConstraint:logoWidth];

}

@end
