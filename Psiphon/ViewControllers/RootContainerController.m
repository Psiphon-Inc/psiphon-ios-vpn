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

// RootContainerController is the application's main window's root view controller.
//
// RootContainerController handles presenting onboarding screen when needed, and switching
// to the main UI when the onboarding is finished.
// It handles showing a loading screen on top of the MainViewController when requested.
//
// Notes on view controllers lifecycle methods:
//  - viewWillAppear is called before the view is added to the window's hierarchy.
//  - It will also get called before [viewController.view layoutSubViews]
//
//  - viewDidAppear is called after the view added to the window's view hierarchy.
//  - It will also get called after [viewController.view layoutSubViews]
//
//  - viewWillDisappear is called before the view is removed from the window's view hierarchy.
//  - viewDidDisappear is called after the views is removed from the windows's view hierarchy.

#import <ReactiveObjC/RACSignal.h>
#import "RootContainerController.h"
#import "LaunchScreenViewController.h"
#import "Logging.h"
#import "ContainerDB.h"
#import "NSDate+Comparator.h"
#import "OnboardingViewController.h"
#import "RACCompoundDisposable.h"

// Apple documentation for creating custom container view controllers:
// https://developer.apple.com/library/content/featuredarticles/ViewControllerPGforiPhoneOS/ImplementingaContainerViewController.html
// https://developer.apple.com/videos/play/wwdc2011/102/

@interface RootContainerController () <OnboardingViewControllerDelegate>

@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@end

@implementation RootContainerController

// Force portrait orientation
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
    }
    return self;
}

- (void)dealloc {
    [self.compoundDisposable dispose];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view setBackgroundColor:[UIColor blackColor]];

    // If has accepted the latest privacy policy and vpn configuration has been installed,
    // then show this
    ContainerDB *containerDB = [[ContainerDB alloc] init];
    NSDate *_Nullable privacyPolicyAcceptedDate = [containerDB lastAcceptedPrivacyPolicy];

    if (!privacyPolicyAcceptedDate ||
        [privacyPolicyAcceptedDate before:[containerDB lastPrivacyPolicyUpdate]]) {
        [self switchToOnboarding];
    } else {
        [self switchToMainScreenAndStartVPN:FALSE];
    }
}

- (void)switchToOnboarding {
    // onboarding view controller should always be the first view controller.
    assert([self.childViewControllers count] == 0);
    OnboardingViewController *onboardingViewController = [[OnboardingViewController alloc] init];
    onboardingViewController.delegate = self;
    [self addAndDisplayChildVC:onboardingViewController];
}

- (void)switchToMainScreenAndStartVPN:(BOOL)startVPN {
    assert([self.childViewControllers count] == 0);
    RootContainerController *__weak weakSelf = self;

    MainViewController *mainViewController = [[MainViewController alloc]
      initWithStartingVPN:startVPN];
    [self addAndDisplayChildVC:mainViewController];

    LaunchScreenViewController *loadingViewController = [[LaunchScreenViewController alloc] init];
    [self addAndDisplayChildVC:loadingViewController];

    // Subscribes to the MainViewController's loading signal, to remove the launch screen
    // once the loading is done.
    __block RACDisposable *disposable = [mainViewController.activeStateLoadingSignal
      subscribeNext:^(RACUnit *x) {
          [weakSelf removeLaunchScreen];
      } error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];
}

- (void)removeLaunchScreen {
    assert([self.childViewControllers count] == 2);

    // LaunchScreenViewController should be the last child view controller.
    LaunchScreenViewController *loadingViewController = self.childViewControllers[1];

    [UIView animateWithDuration:0.8 animations:^{
        loadingViewController.view.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self removeChildVC:loadingViewController];
    }];
}

- (void)addAndDisplayChildVC:(UIViewController *)viewController {
    // The order of method calls is what UIKit expects, and should not be changed.
    [self addChildViewController:viewController];
    viewController.view.frame = self.view.bounds;
    [self.view addSubview:viewController.view];
    [viewController didMoveToParentViewController:self];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)removeChildVC:(UIViewController *)viewController {
    // The order of method calls is what UIKit expects, and should not be changed.
    [viewController willMoveToParentViewController:nil];
    [viewController.view removeFromSuperview];
    [viewController removeFromParentViewController];
    [self setNeedsStatusBarAppearanceUpdate];
}

#pragma mark - Status bar delegation

// The last child view controller added, is the one currently being displayed full-screen.
- (UIViewController *)childViewControllerForStatusBarStyle {
    return [self.childViewControllers lastObject];
}

// The last child view controller added, is the one currently being displayed full-screen.
- (UIViewController *)childViewControllerForStatusBarHidden {
    return [self.childViewControllers lastObject];
}

#pragma mark - OnboardingViewController delegate methods

- (void)onboardingFinished:(OnboardingViewController *)onboardingViewController {
    assert([self.childViewControllers count] == 1);
    [self removeChildVC:onboardingViewController];
    [self switchToMainScreenAndStartVPN:TRUE];
}

#pragma mark - Public methods

// reloadMainViewControllerAndImmediatelyOpenSettings destroys the current MainViewController,
// and creates a new one and loads it.
- (void)reloadMainViewControllerAndImmediatelyOpenSettings {
    assert([self.childViewControllers count] == 1);
    MainViewController *mainViewController = self.childViewControllers[0];

    // Removes current child.
    [self removeChildVC:mainViewController];

    // Creates new child MainViewController, and adds its view to current root view hierarchy.
    mainViewController = [[MainViewController alloc] initWithStartingVPN:FALSE];
    mainViewController.openSettingImmediatelyOnViewDidAppear = TRUE;
    [self addAndDisplayChildVC:mainViewController];
}

@end
