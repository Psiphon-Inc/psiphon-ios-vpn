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

#import "DebugViewController.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "DebugLogViewController.h"
#import "PsiFeedbackLogger.h"
#import "DebugToolboxViewController.h"

#if DEBUG || DEV_RELEASE
@implementation DebugViewController {
    PsiphonDataSharedDB *sharedDB;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:PsiphonAppGroupIdentifier];

    // Debug Toolbox
    DebugToolboxViewController *toolbox = [[DebugToolboxViewController alloc] init];
    UINavigationController *toolboxNav = [[UINavigationController alloc] initWithRootViewController:toolbox];
    toolboxNav.modalPresentationStyle = UIModalPresentationFullScreen;
    toolboxNav.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

    // Tunnel-core logs tab
    DebugLogViewController *tunnelCore = [[DebugLogViewController alloc]
            initWithLogPath:[sharedDB rotatingLogNoticesPath] title:@"Tunnel Core"];
    UINavigationController *tunnelCoreNav = [[UINavigationController alloc] initWithRootViewController:tunnelCore];
    tunnelCoreNav.modalPresentationStyle = UIModalPresentationFullScreen;
    tunnelCoreNav.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

    // Extension logs tab
    DebugLogViewController *networkExtension = [[DebugLogViewController alloc]
            initWithLogPath:PsiFeedbackLogger.extensionRotatingLogNoticesPath title:@"Extension"];
    UINavigationController *networkExtensionNav = [[UINavigationController alloc] initWithRootViewController:networkExtension];
    networkExtensionNav.modalPresentationStyle = UIModalPresentationFullScreen;
    networkExtensionNav.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

    // Container logs tab
    DebugLogViewController *container = [[DebugLogViewController alloc]
            initWithLogPath:PsiFeedbackLogger.containerRotatingLogNoticesPath title:@"Container"];
    UINavigationController *containerNav = [[UINavigationController alloc] initWithRootViewController:container];
    containerNav.modalPresentationStyle = UIModalPresentationFullScreen;
    containerNav.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

    UIImage *wrench = nil;
    UIImage *atom = nil;
    UIImage *puzzle = nil;
    UIImage *app = nil;
    if (@available(iOS 13.0, *)) {
        wrench = [UIImage systemImageNamed:@"wrench.fill"];
        atom = [UIImage systemImageNamed:@"atom"];
        puzzle = [UIImage systemImageNamed:@"puzzlepiece.extension.fill"];
        app = [UIImage systemImageNamed:@"app.fill"];
    }
    
    toolboxNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Toolbox" image:wrench tag:0];
    tunnelCoreNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Core" image:atom tag:0];
    networkExtensionNav.tabBarItem =  [[UITabBarItem alloc] initWithTitle:@"Extension" image:puzzle tag:1];
    containerNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Container" image:app tag:2];

    NSArray *viewControllers = @[toolboxNav, tunnelCoreNav, networkExtensionNav, containerNav];
    [self setViewControllers:viewControllers animated:FALSE];
}

@end

#endif
