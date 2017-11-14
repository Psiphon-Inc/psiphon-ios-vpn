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

/*
 * RootContainerController is the application's main window's root view controller.
 *
 * RootContainerController provides facility to show and hide the launch screen when needed by calling
 * showLaunchScreen and removeLaunchScreen respectively.
 * Each time showLaunchScreen is called, a new instance of LaunchScreenViewController is created,
 * however only one instance of MainViewController is created for the entire lifetime of this container.
 *
 * This class is designed to be the root view controller of AppDelegate.
 *
 * Notes on view controllers lifecycle methods:
 *  - viewWillAppear is called before the view is added to the window's hierarchy.
 *  - It will also get called before [viewController.view layoutSubViews]
 *
 *  - viewDidAppear is called after the view added to the window's view hierarchy.
 *  - It will also get called after [viewController.view layoutSubViews]
 *
 *  - viewWillDisappear is called before the view is removed from the window's view hierarchy.
 *  - viewDidDisappear is called after the views is removed from the windows's view hierarchy.
 */

#import "RootContainerController.h"
#import "LaunchScreenViewController.h"
#import "Logging.h"

// Apple documentation for creating custom container view controllers:
// https://developer.apple.com/library/content/featuredarticles/ViewControllerPGforiPhoneOS/ImplementingaContainerViewController.html
// https://developer.apple.com/videos/play/wwdc2011/102/

@interface RootContainerController ()

@property (nonatomic, strong, readwrite) MainViewController *mainViewController;

/* launchScreenViewController should always be private. */
@property (nonatomic, strong, readwrite) LaunchScreenViewController *launchScreenViewController;

@end

@implementation RootContainerController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.launchScreenViewController = nil;
        self.mainViewController = nil;
    }
    return self;
}

- (void)viewDidLoad {
    LOG_DEBUG();
    [super viewDidLoad];

    [self.view setBackgroundColor:[UIColor blackColor]];

    // As an optimization, MainViewController will not be loaded into memory (MainViewController's viewDidLoad will
    // not be called) unless removeLaunchScreen has been called before viewDidLoad.
    // This prevents the launch screen from taking too long to show up on the screen.

    // Note that addChildViewController: has nothing to do with
    // ViewController lifecycle methods.
    self.mainViewController = [[MainViewController alloc] init];
    [self addChildViewController:self.mainViewController];
    [self displayChildVC:self.mainViewController];

    self.launchScreenViewController = [[LaunchScreenViewController alloc] init];
    [self addChildViewController:self.launchScreenViewController];
    [self displayChildVC:self.launchScreenViewController];
}

// Note: addChildViewController should be called before a view controller can be displayed.
- (void)displayChildVC:(UIViewController *)viewController {
    LOG_DEBUG();
    // The order of method calls is what UIKit expects, and should not be changed.
    viewController.view.frame = self.view.bounds;
    [self.view addSubview:viewController.view];
    [viewController didMoveToParentViewController:self];
    [self setNeedsStatusBarAppearanceUpdate];
}

// removeChildVC removes the given view controller from the container's children.
- (void)removeChildVC:(UIViewController *)viewController {
    // The order of method calls is what UIKit expects, and should not be changed.
    [viewController willMoveToParentViewController:nil];
    [viewController.view removeFromSuperview];
    [viewController removeFromParentViewController];
    [self setNeedsStatusBarAppearanceUpdate];
}

#pragma mark - Status bar delegation

- (UIViewController *)childViewControllerForStatusBarStyle {
    return [self.childViewControllers lastObject];
}

- (UIViewController *)childViewControllerForStatusBarHidden {
    return [self.childViewControllers lastObject];
}

#pragma mark - Public methods

/**
 * Destroys the current mainViewController, and creates a new one and loads it.
 */
- (void)reloadMainViewController {
    if ([self.childViewControllers containsObject:self.mainViewController]) {
        // Removes current child.
        [self removeChildVC:self.mainViewController];

        // Creates new child MainViewController, and adds its view to current root view hierarchy.
        self.mainViewController = [[MainViewController alloc] init];
        [self addChildViewController:self.mainViewController];
        [self displayChildVC:self.mainViewController];
    }
}

/**
 * Adds LaunchScreenViewController as a child of the container.
 * NO-OP if the view controller was already added.
 */
- (void)showLaunchScreen {
    LOG_DEBUG();
    if (!self.viewLoaded) {
        // Launch screen will load sometime after viewDidLoad returns. Return immediately.
        return;
    }

    if (self.launchScreenViewController) {
        // Launch screen is not previously removed. Return immediately.
        return;
    }

    self.launchScreenViewController = [[LaunchScreenViewController alloc] init];
    [self addChildViewController:self.launchScreenViewController];
    [self displayChildVC:self.launchScreenViewController];
}

/**
 * Removes the LaunchScreenViewController from the container.
 * If the container hasn't been loaded yet, calling this method will prevent
 * the launch screen from being launched when the container loads.
 *
 * If this is the first time launch screen is being removed, MainViewController's view
 * will be added to the container's root view.
 * NO-OP if the view controller was already removed.
 */
- (void)removeLaunchScreen {
    LOG_DEBUG();
    if ([self.childViewControllers containsObject:self.launchScreenViewController]) {

        [UIView animateWithDuration:0.8 animations:^{
            self.launchScreenViewController.view.alpha = 0.0;
        } completion:^(BOOL finished) {
            [self removeChildVC:self.launchScreenViewController];
            self.launchScreenViewController = nil;
        }];

    }
}

@end
