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

#import <PsiphonTunnel/Reachability.h>
#import "AppDelegate.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "Notifier.h"
#import "RegionAdapter.h"
#import "VPNManager.h"
#import "AdManager.h"
#import "Logging.h"
#import "IAPHelper.h"
#import "IAPViewController.h"
#import "MPInterstitialAdController.h"
#import "RootContainerController.h"
#import "UIAlertController+Delegate.h"

@interface AppDelegate ()
@end

@implementation AppDelegate {
    VPNManager *vpnManager;
    AdManager *adManager;
    PsiphonDataSharedDB *sharedDB;
    Notifier *notifier;

    BOOL shownHomepage;

    RootContainerController *rootContainerController;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        vpnManager = [VPNManager sharedInstance];
        adManager = [AdManager sharedInstance];
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        notifier = [[Notifier alloc] initWithAppGroupIdentifier:APP_GROUP_IDENTIFIER];

        shownHomepage = FALSE;
    }
    return self;
}

+ (AppDelegate *)sharedAppDelegate {
    return (AppDelegate *)[UIApplication sharedApplication].delegate;
}

+ (BOOL)isRunningUITest {
#ifdef DEBUG
    static BOOL runningUITest;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"FASTLANE_SNAPSHOT"]) {
            NSDictionary *environmentDictionary = [[NSProcessInfo processInfo] environment];
            if (environmentDictionary[@"PsiphonUITestEnvironment"] != nil) {
                runningUITest = TRUE;
            }
        }

    });
    return runningUITest;
#else
    return FALSE;
#endif
}

- (void)onVPNStatusDidChange {
    if ([vpnManager getVPNStatus] == VPNStatusDisconnected
        || [vpnManager getVPNStatus] == VPNStatusRestarting) {
        shownHomepage = FALSE;
    }
}

# pragma mark - Lifecycle methods

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self initializeDefaults];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAdsLoaded)
                                                 name:@kAdsDidLoad object:adManager];

    [[IAPHelper sharedInstance] startProductsRequest];

    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    LOG_DEBUG();
    // Override point for customization after application launch.
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    rootContainerController = [[RootContainerController alloc] init];
    self.window.rootViewController = rootContainerController;
    // UIKit always waits for application:didFinishLaunchingWithOptions:
    // to return before making the window visible on the screen.
    [self.window makeKeyAndVisible];

    [self loadAdsIfNeeded];

    // Listen for VPN status changes from VPNManager.
    [[NSNotificationCenter defaultCenter]
      addObserver:self selector:@selector(onVPNStatusDidChange) name:@kVPNStatusChangeNotificationName object:vpnManager];

    // Listen for the network extension messages.
    [self listenForNEMessages];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    LOG_DEBUG();
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    LOG_DEBUG();
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.

    [[UIApplication sharedApplication] ignoreSnapshotOnNextApplicationLaunch];
    [notifier post:@"D.applicationDidEnterBackground"];
    [sharedDB updateAppForegroundState:NO];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    LOG_DEBUG();
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.

    [self loadAdsIfNeeded];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    LOG_DEBUG();
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    [sharedDB updateAppForegroundState:YES];

    // If the extension has been waiting for the app to come into foreground,
    // send the VPNManager startVPN message again.
    dispatch_async(dispatch_get_main_queue(), ^{
        // If the tunnel is in Connected state, and we're now showing ads
        // send startVPN message.
        if (![adManager untunneledInterstitialIsShowing] && [vpnManager isTunnelConnected]) {
            [vpnManager startVPN];
        }
    });
}

- (void)applicationWillTerminate:(UIApplication *)application {
    LOG_DEBUG();
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)initializeDefaults {
    [PsiphonClientCommonLibraryHelpers initializeDefaultsForPlistsFromRoot:@"Root.inApp"];
}

- (void)reloadMainViewController {
    LOG_DEBUG();
    [rootContainerController reloadMainViewController];
    rootContainerController.mainViewController.openSettingImmediatelyOnViewDidAppear = TRUE;
}

#pragma mark - Ads

- (void)loadAdsIfNeeded {

    if ([adManager shouldShowUntunneledAds]
      && ![adManager untunneledInterstitialIsReady]
      && ![adManager untunneledInterstitialHasShown]
      && ![vpnManager startStopButtonPressed]) {

        [rootContainerController showLaunchScreen];

        dispatch_async(dispatch_get_main_queue(), ^{
                [adManager initializeAds];
        });

    } else {
        // Removes launch screen if already showing.
        [rootContainerController removeLaunchScreen];
    }
}

// Returns the ViewController responsible for presenting ads.
- (UIViewController *)getAdsPresentingViewController {
    return rootContainerController.mainViewController;
}

- (void)onAdsLoaded {
    LOG_DEBUG();
    [rootContainerController removeLaunchScreen];
}

- (void)launchScreenFinished {
    LOG_DEBUG();
    [rootContainerController removeLaunchScreen];
}

#pragma mark - Network Extension

- (void)listenForNEMessages {
    [notifier listenForNotification:@"NE.newHomepages" listener:^{
        LOG_DEBUG(@"Received notification NE.newHomepages");
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (!shownHomepage) {
                NSArray<Homepage *> *homepages = [sharedDB getHomepages];
                if (homepages && [homepages count] > 0) {
                    NSUInteger randIndex = arc4random() % [homepages count];
                    Homepage *homepage = homepages[randIndex];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[UIApplication sharedApplication] openURL:homepage.url options:@{}
                                                 completionHandler:^(BOOL success) {
                                                     shownHomepage = success;
                                                 }];
                    });
                }
            }
        });
    }];

    [notifier listenForNotification:@"NE.tunnelConnected" listener:^{
        LOG_DEBUG(@"Received notification NE.tunnelConnected");
        // Check if user has an active subscription but the receipt is not valid.
        IAPHelper *iapHelper = [IAPHelper sharedInstance];
        if([iapHelper hasActiveSubscriptionForDate:[NSDate date]] && ![iapHelper verifyReceipt]) {
            // Stop the VPN and prompt user to refresh app receipt.
            [vpnManager stopVPN];
            NSString *alertTitle = NSLocalizedStringWithDefaultValue(@"BAD_RECEIPT_ALERT_TITLE", nil, [NSBundle mainBundle], @"Invalid app receipt", @"Alert title informing user that app receipt is not valid");

            NSString *alertMessage = NSLocalizedStringWithDefaultValue(@"BAD_RECEIPT_ALERT_MESSAGE", nil, [NSBundle mainBundle], @"Your subscription receipt cannot be verified, please refresh it and try again.", @"Alert message informing user that subscription receipt cannot be verified");

            UIAlertController *alert = [UIAlertController
                                        alertControllerWithTitle:alertTitle
                                        message:alertMessage
                                        preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *defaultAction = [UIAlertAction
                                            actionWithTitle:NSLocalizedStringWithDefaultValue(@"OK_BUTTON", nil, [NSBundle mainBundle], @"OK", @"Alert OK Button")
                                            style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                IAPViewController *iapViewController = [[IAPViewController alloc]init];
                                                iapViewController.openedFromSettings = NO;
                                                UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:iapViewController];
                                                [rootContainerController presentViewController:navController animated:YES completion:nil];
                                            }];
            [alert addAction:defaultAction];
            [alert presentFromTopController];
            return;
        }

        // Check if user has an active subscription in the device's time
        // If NO - do nothing
        // If YES - proceed with checking the subscription against server timestamp
        if([[IAPHelper sharedInstance]hasActiveSubscriptionForDate:[NSDate date]]) {
            // The following code adapted from
            // https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/DataFormatting/Articles/dfDateFormatting10_4.html
            static NSDateFormatter *sRFC3339DateFormatter;
            static dispatch_once_t once;
            dispatch_once(&once, ^{
                sRFC3339DateFormatter = [[NSDateFormatter alloc] init];
                sRFC3339DateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
                sRFC3339DateFormatter.dateFormat = @"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'";
                sRFC3339DateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            });

            NSString *serverTimestamp = [sharedDB getServerTimestamp];
            NSDate *serverDate = [sRFC3339DateFormatter dateFromString:serverTimestamp];
            if (serverDate != nil) {
                if(![[IAPHelper sharedInstance]hasActiveSubscriptionForDate:serverDate]) {
                    // User is possibly cheating, terminate the app due to 'Invalid Receipt'.
                    // Stop the tunnel, show alert with title and message
                    // and terminate the app due to 'Invalid Receipt' when user clicks 'OK'.
                    [vpnManager stopVPN];

                    NSString *alertTitle = NSLocalizedStringWithDefaultValue(@"BAD_CLOCK_ALERT_TITLE", nil, [NSBundle mainBundle], @"Clock is out of sync", @"Alert title informing user that the device clock needs to be updated with current time");

                    NSString *alertMessage = NSLocalizedStringWithDefaultValue(@"BAD_CLOCK_ALERT_MESSAGE", nil, [NSBundle mainBundle], @"We've detected the time on your device is out of sync with your time zone. Please update your clock settings and restart the app", @"Alert message informing user that the device clock needs to be updated with current time");

                    UIAlertController *alert = [UIAlertController
                                                alertControllerWithTitle:alertTitle
                                                message:alertMessage
                                                preferredStyle:UIAlertControllerStyleAlert];

                    UIAlertAction *defaultAction = [UIAlertAction
                                                    actionWithTitle:NSLocalizedStringWithDefaultValue(@"OK_BUTTON", nil, [NSBundle mainBundle], @"OK", @"Alert OK Button")
                                                    style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction *action) {
                                                        [[IAPHelper sharedInstance] terminateForInvalidReceipt];
                                                    }];
                    [alert addAction:defaultAction];
                    [alert presentFromTopController];
                    return;
                }
            }
        }

        // If we haven't had a chance to load an Ad, and the
        // tunnel is already connected, give up on the Ad and
        // start the VPN. Otherwise the startVPN message will be
        // sent after the Ad has disappeared.
        if (![adManager untunneledInterstitialIsShowing]) {
            [vpnManager startVPN];
        }

    }];

    [notifier listenForNotification:@"NE.onAvailableEgressRegions" listener:^{ // TODO should be put in a constants file
        LOG_DEBUG(@"Received notification NE.onAvailableEgressRegions");
        // Update available regions
        // TODO: this code is duplicated in MainViewController updateAvailableRegions
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray<NSString *> *regions = [sharedDB getAllEgressRegions];
            [[RegionAdapter sharedInstance] onAvailableEgressRegions:regions];
        });
    }];

    [notifier listenForNotification:@"NE.onAvailableEgressRegions" listener:^{ // TODO should be put in a constants file
        LOG_DEBUG(@"Received notification NE.onAvailableEgressRegions");
        // Update available regions
        // TODO: this code is duplicated in MainViewController updateAvailableRegions
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray<NSString *> *regions = [sharedDB getAllEgressRegions];
            [[RegionAdapter sharedInstance] onAvailableEgressRegions:regions];
        });
    }];
}

@end
