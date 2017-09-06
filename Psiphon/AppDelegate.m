/*
 * Copyright (c) 2015, Psiphon Inc.
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

#import "AppDelegate.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "Notifier.h"
#import "RegionAdapter.h"
#import "VPNManager.h"
#import "AdManager.h"

@interface AppDelegate ()
@end

@implementation AppDelegate {
    VPNManager *vpnManager;
    AdManager *adManager;
    PsiphonDataSharedDB *sharedDB;
    Notifier *notifier;

    // Loading Timer
    NSTimer *loadingTimer;
    NSInteger timerCount;

    BOOL shownHomepage;
    
    // ViewController
    MainViewController *mainViewController;
    LaunchScreenViewController *launchScreenViewController;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        vpnManager = [VPNManager sharedInstance];
        adManager = [AdManager sharedInstance];
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        
        mainViewController = [[MainViewController alloc] init];
        launchScreenViewController = [[LaunchScreenViewController alloc] init];
    }
    return self;
}

+ (AppDelegate *)sharedAppDelegate {
    return (AppDelegate *)[UIApplication sharedApplication].delegate;
}

- (MainViewController *)getMainViewController {
    return mainViewController;
}

- (void) vpnStatusDidChange {
    if ([vpnManager getVPNStatus] == VPNStatusDisconnected
      || [vpnManager getVPNStatus] == VPNStatusRestarting) {
        shownHomepage = FALSE;
    }
}

# pragma mark - Lifecycle methods

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	[self initializeDefaults];
    [[NSNotificationCenter defaultCenter]
      addObserver:self selector:@selector(switchViewControllerWhenAdsLoaded) name:@kAdsDidLoad object:adManager];

	return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSLog(@"AppDelegate: application:didFinishLaunchingWithOptions:");
    // Override point for customization after application launch.
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    // TODO: if VPN disconnected, launch with animation, else launch with MainViewController.
    [self setRootViewController];

    [self.window makeKeyAndVisible];

    shownHomepage = FALSE;
    // Listen for VPN status changes from VPNManager.
    [[NSNotificationCenter defaultCenter]
      addObserver:self selector:@selector(vpnStatusDidChange) name:@kVPNStatusChangeNotificationName object:vpnManager];

    // Listen for the network extension messages.
    [self listenForNEMessages];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    NSLog(@"AppDelegate: applicationWillResignActive");
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    [sharedDB updateAppForegroundState:NO];
    [notifier post:@"D.appWillResignActive"];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    NSLog(@"AppDelegate: applicationDidEnterBackground");
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    NSLog(@"AppDelegate: applicationWillEnterForeground");
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    
    [self setRootViewController];
    
    // TODO: init MainViewController.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    NSLog(@"AppDelegate: applicationDidBecomeActive");
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    [sharedDB updateAppForegroundState:YES];

    // If the extension has been waiting for the app to come into foreground,
    // send the VPNManager startVPN message again.
    dispatch_async(dispatch_get_main_queue(), ^{
        // If the tunnel is in Connected state, and we're now showing ads
        // send startVPN message.
        if (!adManager.adIsShowing && [vpnManager isTunnelConnected]) {
            [vpnManager startVPN];
        }
    });
}

- (void)applicationWillTerminate:(UIApplication *)application {
    NSLog(@"AppDelegate: applicationWillTerminate");
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)initializeDefaults {
	[PsiphonClientCommonLibraryHelpers initializeDefaultsFor:@"Root.inApp.plist"];
	[PsiphonClientCommonLibraryHelpers initializeDefaultsFor:@"Feedback.plist"];
}

#pragma mark - View controller switch

- (void) setRootViewController {
    // TODO: if VPN disconnected, launch with animation, else launch with MainViewController.
    if (([vpnManager getVPNStatus] == VPNStatusDisconnected || [vpnManager getVPNStatus] == VPNStatusInvalid) &&
        ![adManager adIsReady]) {
        [adManager initializeAds];
        self.window.rootViewController = launchScreenViewController;
        [self startLaunchingScreenTimer];
    } else {
        self.window.rootViewController = mainViewController;
    }
}

- (void) switchViewControllerWhenAdsLoaded {
    [loadingTimer invalidate];
    [self changeRootViewController:mainViewController];
}

- (void) switchViewControllerWhenExpire:(NSTimer*)timer {
    if (timerCount == 0) {
        // TODO: Test if videoFile observer been removed before switch view controller, if not, need to remove that.
        //    if (self.videoFile != nil) {
        //        [self.videoFile removeObserver:self forKeyPath:@"status"];
        //    }
        [loadingTimer invalidate];
        [self changeRootViewController:mainViewController];
    }
    timerCount -=1;
    launchScreenViewController.secondLabel.text = [NSString stringWithFormat:@"%ld", (long)timerCount];
    launchScreenViewController.progressView.progress = (10 - timerCount)/10.0f;
}

- (void) startLaunchingScreenTimer {
    timerCount = 10;
    if (!loadingTimer || ![loadingTimer isValid]) {
        loadingTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                         target:self
                                                       selector:@selector(switchViewControllerWhenExpire:)
                                                       userInfo:nil
                                                        repeats:YES];
    }
}

- (void)changeRootViewController:(UIViewController*)viewController {
    if (!self.window.rootViewController) {
        self.window.rootViewController = viewController;
        return;
    }
    
    if (self.window.rootViewController == viewController) {
        return;
    }

    UIViewController *prevViewController = self.window.rootViewController;

    UIView *snapShot = [self.window snapshotViewAfterScreenUpdates:YES];
    [viewController.view addSubview:snapShot];

    self.window.rootViewController = viewController;

    [prevViewController dismissViewControllerAnimated:NO completion:^{
        // Remove the root view in case it is still showing
        [prevViewController.view removeFromSuperview];
    }];

    [UIView animateWithDuration:.3 animations:^{
        snapShot.layer.opacity = 0;
        snapShot.layer.transform = CATransform3DMakeScale(1.5, 1.5, 1.5);
    } completion:^(BOOL finished) {
        [snapShot removeFromSuperview];
    }];
}

#pragma mark - Network Extension

- (void)listenForNEMessages {
    [notifier listenForNotification:@"NE.newHomepages" listener:^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (!shownHomepage) {
                NSArray<Homepage *> *homepages = [sharedDB getAllHomepages];
                if ([homepages count] > 0) {
                    NSUInteger randIndex = arc4random() % [homepages count];
                    Homepage *homepage = homepages[randIndex];

                    [[UIApplication sharedApplication] openURL:homepage.url options:@{}
                                             completionHandler:^(BOOL success) {
                                                 shownHomepage = success;
                                             }];

                }
            }
        });
    }];

    [notifier listenForNotification:@"NE.tunnelConnected" listener:^{
        NSLog(@"received NE.tunnelConnected");
        // If we haven't had a chance to load an Ad, and the
        // tunnel is already connected, give up on the Ad and
        // start the VPN. Otherwise the startVPN message will be
        // sent after the Ad has disappeared.
        if (!adManager.adIsShowing) {
            [vpnManager startVPN];
        }
    }];

    [notifier listenForNotification:@"NE.onAvailableEgressRegions" listener:^{ // TODO should be put in a constants file
        // Update available regions
        // TODO: this code is duplicated in MainViewController updateAvailableRegions
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray<NSString *> *regions = [sharedDB getAllEgressRegions];
            [[RegionAdapter sharedInstance] onAvailableEgressRegions:regions];
        });
    }];
}

@end
