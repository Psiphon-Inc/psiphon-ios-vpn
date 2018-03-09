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
#import "AdManager.h"
#import "EmbeddedServerEntries.h"
#import "IAPViewController.h"
#import "Logging.h"
#import "MPInterstitialAdController.h"
#import "Notifier.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "PsiphonConfigFiles.h"
#import "PsiphonDataSharedDB.h"
#import "RegionAdapter.h"
#import "RootContainerController.h"
#import "SharedConstants.h"
#import "UIAlertController+Delegate.h"
#import "VPNManager.h"
#import "AdManager.h"
#import "Logging.h"
#import "IAPStoreHelper.h"
#import "NEBridge.h"
#import "DispatchUtils.h"
#import "PsiFeedbackLogger.h"

NSNotificationName const AppDelegateSubscriptionDidExpireNotification = @"AppDelegateSubscriptionDidExpireNotification";
NSNotificationName const AppDelegateSubscriptionDidActivateNotification = @"AppDelegateSubscriptionDidActivateNotification";

@implementation AppDelegate {
    VPNManager *vpnManager;
    AdManager *adManager;
    PsiphonDataSharedDB *sharedDB;
    Notifier *notifier;
    NSTimer *subscriptionCheckTimer;

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

+ (BOOL)isFirstRunOfAppVersion {
    static BOOL firstRunOfVersion;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
        NSString *lastLaunchAppVersion = [userDefaults stringForKey:@"LastCFBundleVersion"];
        if ([appVersion isEqualToString:lastLaunchAppVersion]) {
            firstRunOfVersion = FALSE;
        } else {
            firstRunOfVersion = TRUE;
            [userDefaults setObject:appVersion forKey:@"LastCFBundleVersion"];
        }
    });
    return firstRunOfVersion;
}

+ (BOOL)isRunningUITest {
#if DEBUG
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

# pragma mark - Lifecycle methods

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self initializeDefaults];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onAdsLoaded)
                                                 name:AdManagerAdsDidLoadNotification
                                               object:adManager];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onUpdatedSubscriptionDictionary)
                                                 name:IAPHelperUpdatedSubscriptionDictionaryNotification
                                               object:nil];

    [[IAPStoreHelper sharedInstance] startProductsRequest];

    if ([AppDelegate isFirstRunOfAppVersion]) {
        [self updateAvailableEgressRegionsOnFirstRunOfAppVersion];
    }

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
      addObserver:self selector:@selector(onVPNStatusDidChange) name:VPNManagerStatusDidChangeNotification object:vpnManager];

    // Listen for the network extension messages.
    [self listenForNEMessages];

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    LOG_DEBUG();
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    [sharedDB updateAppForegroundState:YES];


    // If the extension has been waiting for the app to come into foreground,
    // send the VPNManager startVPN message again.
    dispatch_async_main(^{
        // If the tunnel is in Connected state, and we're now showing ads
        // send startVPN message.
        if (![adManager untunneledInterstitialIsShowing]) {
            [vpnManager queryNEIsTunnelConnected:^(BOOL tunnelIsConnected) {
                if (tunnelIsConnected) {
                    [vpnManager startVPN];
                }
            }];
        }
    });

    // Kill extension if it's become a zombie.
    [vpnManager killExtensionIfZombie];

    // Starts subscription expiry timer if there is an active subscription.
    [self subscriptionExpiryTimer];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    LOG_DEBUG();
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.

    // Cancel subscription expiry timer if active.
    [subscriptionCheckTimer invalidate];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    LOG_DEBUG();
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.

    [[UIApplication sharedApplication] ignoreSnapshotOnNextApplicationLaunch];
    [notifier post:NOTIFIER_APP_DID_ENTER_BACKGROUND];
    [sharedDB updateAppForegroundState:NO];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    LOG_DEBUG();
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.

    [self loadAdsIfNeeded];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    LOG_DEBUG();
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

#pragma mark -

- (void)initializeDefaults {
    [PsiphonClientCommonLibraryHelpers initializeDefaultsForPlistsFromRoot:@"Root.inApp"];
}

- (void)reloadMainViewController {
    LOG_DEBUG();
    [rootContainerController reloadMainViewController];
    rootContainerController.mainViewController.openSettingImmediatelyOnViewDidAppear = TRUE;
}

- (void)onVPNStatusDidChange {
    if ([vpnManager VPNStatus] == VPNStatusDisconnected
      || [vpnManager VPNStatus] == VPNStatusRestarting) {
        shownHomepage = FALSE;
    }
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

#pragma mark - Embedded Server Entries

/*!
 * @brief Updates available egress regions from embedded server entries.
 *
 * This function should only be called once per app version on first launch.
 */
- (void)updateAvailableEgressRegionsOnFirstRunOfAppVersion {
    NSString *embeddedServerEntriesPath = [PsiphonConfigFiles embeddedServerEntriesPath];
    NSArray *embeddedEgressRegions = [EmbeddedServerEntries egressRegionsFromFile:embeddedServerEntriesPath];

    LOG_DEBUG("Available embedded egress regions: %@.", embeddedEgressRegions);

    if ([embeddedEgressRegions count] > 0) {
        [sharedDB insertNewEmbeddedEgressRegions:embeddedEgressRegions];
    } else {
        [PsiFeedbackLogger error:@"Error no egress regions found in %@.", embeddedServerEntriesPath];
    }
}

#pragma mark - Network Extension

- (void)listenForNEMessages {
    [notifier listenForNotification:NOTIFIER_NEW_HOMEPAGES listener:^{
        LOG_DEBUG(@"Received notification NE.newHomepages");
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (!shownHomepage) {
                // Only opens landing page if the VPN is active.
                // Landing page should not be opened outside of the tunnel.
                if ([vpnManager isVPNActive]) {

                    NSArray<Homepage *> *homepages = [sharedDB getHomepages];
                    if (homepages && [homepages count] > 0) {
                        NSUInteger randIndex = arc4random() % [homepages count];
                        Homepage *homepage = homepages[randIndex];

                        [PsiFeedbackLogger infoWithType:@"LandingPage" message:@"open landing page with VPN status %ld", (long) [vpnManager VPNStatus]];

                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[UIApplication sharedApplication] openURL:homepage.url options:@{}
                                                     completionHandler:^(BOOL success) {
                                                         shownHomepage = success;
                                                     }];
                        });
                    }
                }
            }
        });
    }];

    [notifier listenForNotification:NOTIFIER_TUNNEL_CONNECTED listener:^{
        LOG_DEBUG(@"Received notification NE.tunnelConnected");

        // If we haven't had a chance to load an Ad, and the
        // tunnel is already connected, give up on the Ad and
        // start the VPN. Otherwise the startVPN message will be
        // sent after the Ad has disappeared.
        if (![adManager untunneledInterstitialIsShowing]) {
            [vpnManager startVPN];
        }
    }];

    [notifier listenForNotification:NOTIFIER_ON_AVAILABLE_EGRESS_REGIONS listener:^{ // TODO should be put in a constants file
        LOG_DEBUG(@"Received notification NE.onAvailableEgressRegions");
        // Update available regions
        // TODO: this code is duplicated in MainViewController updateAvailableRegions
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray<NSString *> *regions = [sharedDB getAllEgressRegions];
            [[RegionAdapter sharedInstance] onAvailableEgressRegions:regions];
        });
    }];
}

#pragma mark - Subscription

- (void)subscriptionExpiryTimer {

    __weak AppDelegate *weakSelf = self;

    dispatch_async_global(^{
        NSDate *expiryDate;
        BOOL activeSubscription = [IAPStoreHelper hasActiveSubscriptionForDate:[NSDate date] getExpiryDate:&expiryDate];

        dispatch_async_main(^{
            if (activeSubscription) {
                NSTimeInterval interval = [expiryDate timeIntervalSinceNow];
                
                if (interval > 0) {
                    // Checks if another timer is already running.
                    if (![subscriptionCheckTimer isValid]) {
                        subscriptionCheckTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:NO block:^(NSTimer *timer) {
                            [weakSelf subscriptionExpiryTimer];
                        }];
                    }
                }
            } else {
                // Instead of subscribing to the notification in this class, calls the handler directly.
                [weakSelf onSubscriptionExpired];
                
                // Notifies all interested listeners that there is no active subscription.
                [[NSNotificationCenter defaultCenter] postNotificationName:AppDelegateSubscriptionDidExpireNotification object:nil];
            }
        });
    });
}

- (void)onSubscriptionExpired {

    // Disables Connect On Demand setting of the VPN Configuration.
    [vpnManager updateVPNConfigurationOnDemandSetting:FALSE completionHandler:^(NSError *error) {
        // Do nothing.
    }];
}

- (void)onSubscriptionActivated {
    [self subscriptionExpiryTimer];

    // Asks the extension to perform a subscription check if it is running currently.
    if ([vpnManager isVPNActive]) {
        [notifier post:NOTIFIER_FORCE_SUBSCRIPTION_CHECK];
    }

    // Checks if user previously preferred to have Connect On Demand enabled,
    // Re-enable it upon subscription since it may have been disabled if the previous subscription expired.
    BOOL userPreferredOnDemandSetting = [[NSUserDefaults standardUserDefaults] boolForKey:SettingsConnectOnDemandBoolKey];
    [vpnManager updateVPNConfigurationOnDemandSetting:userPreferredOnDemandSetting completionHandler:^(NSError *error) {
        // Do nothing.
    }];

}

- (void)onUpdatedSubscriptionDictionary {

    if (![adManager shouldShowUntunneledAds]) {
        // if user subscription state has changed to valid
        // try to deinit ads if currently not showing and hide adLabel
        [adManager initializeAds];
    }

    __weak AppDelegate *weakSelf = self;

    dispatch_async_global(^{

        BOOL isSubscribed = [IAPStoreHelper hasActiveSubscriptionForNow];

        dispatch_async_main(^{

            if (isSubscribed) {
                [weakSelf onSubscriptionActivated];

                [[NSNotificationCenter defaultCenter] postNotificationName:AppDelegateSubscriptionDidActivateNotification object:nil];
            }
        });
    });
}

@end
