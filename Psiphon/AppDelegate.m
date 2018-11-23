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
#import <ReactiveObjC/RACTuple.h>
#import <NetworkExtension/NetworkExtension.h>
#import <ReactiveObjC/RACScheduler.h>
#import <stdatomic.h>
#import "AppDelegate.h"
#import "AdManager.h"
#import "AppInfo.h"
#import "EmbeddedServerEntries.h"
#import "IAPViewController.h"
#import "Logging.h"
#import "MPInterstitialAdController.h"
#import "Notifier.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "PsiphonConfigReader.h"
#import "PsiphonDataSharedDB.h"
#import "RootContainerController.h"
#import "SharedConstants.h"
#import "UIAlertController+Additions.h"
#import "VPNManager.h"
#import "AdManager.h"
#import "Logging.h"
#import "IAPStoreHelper.h"
#import "NEBridge.h"
#import "DispatchUtils.h"
#import "PsiFeedbackLogger.h"
#import "RACSignal.h"
#import "RACSignal+Operations2.h"
#import "NSError+Convenience.h"
#import "RACCompoundDisposable.h"
#import "RACSignal+Operations.h"
#import "RACReplaySubject.h"
#import "Asserts.h"
#import "PsiCashClient.h"
#import "PsiCashTypes.h"

#if DEBUG
#define kMaxAdLoadingTimeSecs 1.f
#else
#define kMaxAdLoadingTimeSecs 10.f
#endif

// Number of seconds to wait for tunnel status to become "Connected", after the landing page notification
// is received from the extension.
#define kLandingPageTimeoutSecs 1.0

// Number of seconds to wait for PsiCashClient to emit an auth package with an earner token, after the
// landing page notification is received from the extension.
#define kPsiCashAuthPackageWithEarnerTokenTimeoutSecs 3.0

/** Number of seconds to wait before checking reachability status after receiving
 * NotifierNetworkConnectivityFailed from the extension */
NSTimeInterval const InternetReachabilityCheckTimeout = 10.0;

PsiFeedbackLogType const LandingPageLogType = @"LandingPage";

@interface AppDelegate () <NotifierObserver>

// Public properties

// subscriptionStatus should only be sent events to from the main thread.
// Emits type UserSubscriptionStatus
@property (nonatomic, readwrite) RACReplaySubject<NSNumber *> *subscriptionStatus;

// Private properties
@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@property (nonatomic) VPNManager *vpnManager;
@property (nonatomic) PsiphonDataSharedDB *sharedDB;
@property (nonatomic) NSTimer *subscriptionCheckTimer;

// Private state subjects
@property (nonatomic) RACSubject<RACUnit *> *checkExtensionNetworkConnectivityFailedSubject;

@end

@implementation AppDelegate {
    RootContainerController *rootContainerController;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _subscriptionStatus = [RACReplaySubject replaySubjectWithCapacity:1];
        [_subscriptionStatus sendNext:@(UserSubscriptionUnknown)];

        _vpnManager = [VPNManager sharedInstance];
        _sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        _shownLandingPageForCurrentSession = FALSE;
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];

        _checkExtensionNetworkConnectivityFailedSubject = [RACSubject subject];
    }
    return self;
}

- (void)dealloc {
    [self.compoundDisposable dispose];
}

+ (AppDelegate *)sharedAppDelegate {
    return (AppDelegate *)[UIApplication sharedApplication].delegate;
}

#pragma mark - Reactive signals generators

// createAppLoadingSignal emits RACUnit.defaultUnit and completes immediately once all loading signals have completed.
- (RACSignal<RACUnit *> *)createAppLoadingSignal {

    // adsLoadingSignal emits a value when untunneled interstitial ad has loaded or kMaxAdLoadingTimeSecs has passed.
    // If the device in not in untunneled state, this signal makes an emission and then completes immediately, without
    // checking the untunneled interstitial status.
    RACSignal *adsLoadingSignal = [[[VPNManager sharedInstance].lastTunnelStatus
      flattenMap:^RACSignal *(NSNumber *statusObject) {

          VPNStatus s = (VPNStatus) [statusObject integerValue];
          BOOL needAdConsent = [MoPub sharedInstance].shouldShowConsentDialog;

          if (!needAdConsent && (s == VPNStatusDisconnected || s == VPNStatusInvalid)) {

              // Device is untunneled and ad consent is given or not needed,
              // we therefore wait for the ad to load.
              return [[[[AdManager sharedInstance].untunneledInterstitialCanPresent
                filter:^BOOL(NSNumber *adIsReady) {
                    return [adIsReady boolValue];
                }]
                merge:[RACSignal timer:kMaxAdLoadingTimeSecs]]
                take:1];

          } else {
              // Device in _not_ untunneled or we need to show the Ad consent modal screen,
              // wo we will emit RACUnit immediately since no ads will be loaded here.
              return [RACSignal return:RACUnit.defaultUnit];
          }
      }]
      take:1];

    // subscriptionLoadingSignal emits a value when the user subscription status becomes known.
    RACSignal *subscriptionLoadingSignal = [[self.subscriptionStatus
      filter:^BOOL(NSNumber *value) {
          UserSubscriptionStatus s = (UserSubscriptionStatus) [value integerValue];
          return (s != UserSubscriptionUnknown);
      }]
      take:1];

    // Returned signal emits RACUnit and completes immediately after all loading operations are done.
    return [subscriptionLoadingSignal flattenMap:^RACSignal *(NSNumber *value) {
        BOOL subscribed = ([value integerValue] == UserSubscriptionActive);

        if (subscribed) {
            // User is subscribed, dismiss the loading screen immediately.
            return [RACSignal return:RACUnit.defaultUnit];
        } else {
            // User is not subscribed, wait for the adsLoadingSignal.
            return [adsLoadingSignal mapReplace:RACUnit.defaultUnit];
        }
    }];
}

# pragma mark - Lifecycle methods

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onUpdatedSubscriptionDictionary)
                                                 name:IAPHelperUpdatedSubscriptionDictionaryNotification
                                               object:nil];

    // Immediately register to receive notifications from the Network Extension process.
    [[Notifier sharedInstance] registerObserver:self callbackQueue:dispatch_get_main_queue()];

    // Initializes PsiphonClientCommonLibrary.
    [PsiphonClientCommonLibraryHelpers initializeDefaultsForPlistsFromRoot:@"Root.inApp"];


    [[IAPStoreHelper sharedInstance] startProductsRequest];

    if ([AppInfo firstRunOfAppVersion]) {
        [self updateAvailableEgressRegionsOnFirstRunOfAppVersion];

        // Reset Jetsam counter.
        [self.sharedDB resetJetsamCounter];
    }

    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    LOG_DEBUG();

    __weak AppDelegate *weakSelf = self;

    // Override point for customization after application launch.
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    rootContainerController = [[RootContainerController alloc] init];
    self.window.rootViewController = rootContainerController;

    // UIKit always waits for application:didFinishLaunchingWithOptions:
    // to return before making the window visible on the screen.
    [self.window makeKeyAndVisible];

    // Initializes AdManager.
    [[AdManager sharedInstance] initializeAdManager];

    // Listen for VPN status changes from VPNManager.
    __block RACDisposable *disposable = [self.vpnManager.lastTunnelStatus
      subscribeNext:^(NSNumber *statusObject) {
          VPNStatus s = (VPNStatus) [statusObject integerValue];

          if (s == VPNStatusDisconnected || s == VPNStatusRestarting ) {
              // Resets the homepage flag if the VPN has disconnected or is restarting.
              weakSelf.shownLandingPageForCurrentSession = FALSE;
          }

      } error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];

    // Start PsiCash lifecycle
    [[PsiCashClient sharedInstance] scheduleRefreshState];

    // Observe internet reachability status.
    [self.compoundDisposable addDisposable:[self observeNetworkExtensionReachabilityStatus]];

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    LOG_DEBUG();

    __weak AppDelegate *weakSelf = self;

    // Subscribes to the app loading signal, and removes the launch screen once all loading is done.
    __block RACDisposable *disposable = [[self createAppLoadingSignal]
      subscribeNext:^(RACUnit *x) {
          [rootContainerController removeLaunchScreen];
      } error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];
    [self.compoundDisposable addDisposable:disposable];

    // Starts subscription expiry timer if there is an active subscription.
    [self subscriptionExpiryTimer];

    // Before submitting any other work to the VPNManager, update its status.
    [[self.vpnManager checkOrFixVPN] subscribeNext:^(NSNumber *extensionProcessRunning) {
        if ([extensionProcessRunning boolValue]) {
            [weakSelf.checkExtensionNetworkConnectivityFailedSubject sendNext:RACUnit.defaultUnit];
        }
    }];

    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    [self.sharedDB updateAppForegroundState:YES];

    // If the extension has been waiting for the app to come into foreground,
    // send the VPNManager startVPN message again.
    __block RACDisposable *connectedDisposable = [[[RACSignal
      zip:@[
        [[AdManager sharedInstance].adIsShowing take:1],
        [self.vpnManager queryIsPsiphonTunnelConnected],
        [self.vpnManager.lastTunnelStatus take:1],
      ]]
      flattenMap:^RACSignal<RACUnit *> *(RACTuple *tuple) {
          BOOL adIsShowing = [(NSNumber *) tuple.first boolValue];
          BOOL tunnelConnected = [(NSNumber *) tuple.second boolValue];
          VPNStatus vpnStatus = (VPNStatus) [tuple.third integerValue];

          // App has recently been foregrounded.
          // If an ad is not showing, and tunnel is connected, but the VPN status is connecting, then send the
          // start VPN message to the extension.
          if (!adIsShowing && tunnelConnected && vpnStatus == VPNStatusConnecting) {
              return [RACSignal return:RACUnit.defaultUnit];
          }

          return [RACSignal empty];
      }]
      subscribeNext:^(RACUnit *x) {
          [weakSelf.vpnManager startVPN];
      }
      error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:connectedDisposable];
      }
      completed:^{
          [weakSelf.compoundDisposable removeDisposable:connectedDisposable];
      }];

    [self.compoundDisposable addDisposable:connectedDisposable];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    LOG_DEBUG();
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.

    // Cancel subscription expiry timer if active.
    [self.subscriptionCheckTimer invalidate];

    [self.sharedDB updateAppForegroundState:NO];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    LOG_DEBUG();
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.

    [[UIApplication sharedApplication] ignoreSnapshotOnNextApplicationLaunch];
    [[Notifier sharedInstance] post:NotifierAppEnteredBackground];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    LOG_DEBUG();
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.

    // Resets status of the subjects whose state could be stale once the container is foregrounded.
    [self.subscriptionStatus sendNext:@(UserSubscriptionUnknown)];

    [[PsiCashClient sharedInstance] scheduleRefreshState];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    LOG_DEBUG();
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

#pragma mark -

- (void)reloadMainViewController {
    LOG_DEBUG();
    [rootContainerController reloadMainViewController];
    rootContainerController.mainViewController.openSettingImmediatelyOnViewDidAppear = TRUE;
}

#pragma mark - Ads

// Returns the ViewController responsible for presenting ads.
- (UIViewController *)getAdsPresentingViewController {
    return rootContainerController.mainViewController;
}

#pragma mark - Embedded Server Entries

/*!
 * @brief Updates available egress regions from embedded server entries.
 *
 * This function should only be called once per app version on first launch.
 */
- (void)updateAvailableEgressRegionsOnFirstRunOfAppVersion {
    NSString *embeddedServerEntriesPath = PsiphonConfigReader.embeddedServerEntriesPath;
    NSArray *embeddedEgressRegions = [EmbeddedServerEntries egressRegionsFromFile:embeddedServerEntriesPath];

    LOG_DEBUG("Available embedded egress regions: %@.", embeddedEgressRegions);

    if ([embeddedEgressRegions count] > 0) {
        [self.sharedDB setEmbeddedEgressRegions:embeddedEgressRegions];
    } else {
        [PsiFeedbackLogger error:@"Error no egress regions found in %@.", embeddedServerEntriesPath];
    }
}

#pragma mark - Notifier callback

- (void)onMessageReceived:(NotifierMessage)message {

    __weak AppDelegate *weakSelf = self;

    if ([NotifierNewHomepages isEqualToString:message]) {

        LOG_DEBUG(@"Received notification NE.newHomepages");

        // Ignore the notification from the extension, since a landing page has
        // already been shown for the current session.
        if (weakSelf.shownLandingPageForCurrentSession) {
            return;
        }

        // Eagerly set the value to TRUE.
        weakSelf.shownLandingPageForCurrentSession = TRUE;
        
        dispatch_async_global(^{

            // If a landing page is not already shown for the current session, randomly choose
            // a landing page from the list supplied by Psiphon tunnel.

            NSArray<Homepage *> *homepages = [weakSelf.sharedDB getHomepages];

            if (!homepages || [homepages count] == 0) {
                weakSelf.shownLandingPageForCurrentSession = FALSE;
                return;
            }

            NSUInteger randIndex = arc4random() % [homepages count];
            Homepage *homepage = homepages[randIndex];

            RACSignal <RACUnit*>*authPackageSignal = [[[[[PsiCashClient.sharedInstance.clientModelSignal
              filter:^BOOL(PsiCashClientModel * _Nullable model) {
                  if ([model.authPackage hasEarnerToken]) {
                      return TRUE;
                  }
                  return FALSE;
              }]
              map:^id _Nullable(PsiCashClientModel * _Nullable model) {
                  return RACUnit.defaultUnit;
              }]
              take:1]
              timeout:kPsiCashAuthPackageWithEarnerTokenTimeoutSecs onScheduler:RACScheduler.mainThreadScheduler]
              catch:^RACSignal * (NSError * error) {
                  if ([error.domain isEqualToString:RACSignalErrorDomain] && error.code == RACSignalErrorTimedOut) {
                      [PsiFeedbackLogger infoWithType:PsiCashLogType message:@"timeout waiting for earner token, waited %0.1fs", kPsiCashAuthPackageWithEarnerTokenTimeoutSecs];
                      return [RACSignal return:RACUnit.defaultUnit];
                  }
                  return [RACSignal error:error];
              }];

            // Only opens landing page if the VPN is active (or waits up to a maximum of kLandingPageTimeoutSecs
            // for the tunnel status to become "Connected" before opening the landing page).
            // Landing page should not be opened outside of the tunnel.
            //
            __block RACDisposable *disposable = [[[[[[[[weakSelf.vpnManager queryIsExtensionZombie]
              combineLatestWith:self.vpnManager.lastTunnelStatus]
              filter:^BOOL(RACTwoTuple<NSNumber *, NSNumber *> *tuple) {

                  // We're only interested in the Connected status.
                  VPNStatus s = (VPNStatus) [tuple.second integerValue];
                  return (s == VPNStatusConnected);
              }]
              take:1]  // Take 1 to terminate the infinite signal.
              timeout:kLandingPageTimeoutSecs onScheduler:RACScheduler.mainThreadScheduler]
              zipWith:authPackageSignal]
              deliverOnMainThread]
              subscribeNext:^(RACTwoTuple<RACTwoTuple<NSNumber *, NSNumber *>*, RACUnit*> *x) {
                  BOOL isZombie = [x.first.first boolValue];

                  if (isZombie) {
                      weakSelf.shownLandingPageForCurrentSession = FALSE;
                      return;
                  }

                  NEVPNStatus s = weakSelf.vpnManager.tunnelProviderStatus;
                  if (NEVPNStatusConnected == s) {

                      [PsiFeedbackLogger infoWithType:LandingPageLogType message:@"open landing page"];

                      NSURL *url = [PsiCashClient.sharedInstance modifiedHomePageURL:homepage.url];
                      // Not officially documented by Apple, however a runtime warning is generated sometimes
                      // stating that [UIApplication openURL:options:completionHandler:] must be used from
                      // the main thread only.
                      [[UIApplication sharedApplication] openURL:url
                                                         options:@{}
                                               completionHandler:^(BOOL success) {
                                                   weakSelf.shownLandingPageForCurrentSession = success;
                                               }];
                  } else {

                      [PsiFeedbackLogger warnWithType:LandingPageLogType
                                              message:@"fail open with connection status %@", [VPNManager statusTextSystem:s]];
                      weakSelf.shownLandingPageForCurrentSession = FALSE;
                  }

              } error:^(NSError *error) {
                  [PsiFeedbackLogger warnWithType:LandingPageLogType message:@"timeout expired" object:error];
                  [weakSelf.compoundDisposable removeDisposable:disposable];
              } completed:^{
                  [weakSelf.compoundDisposable removeDisposable:disposable];
              }];

            [weakSelf.compoundDisposable addDisposable:disposable];

        });

    } else if ([NotifierTunnelConnected isEqualToString:message]) {
        LOG_DEBUG(@"Received notification NE.tunnelConnected");

        // If we haven't had a chance to load an Ad, and the
        // tunnel is already connected, give up on the Ad and
        // start the VPN. Otherwise the startVPN message will be
        // sent after the Ad has disappeared.
        __block RACDisposable *disposable = [[[AdManager sharedInstance].adIsShowing take:1]
          subscribeNext:^(NSNumber *adIsShowing) {

              if (![adIsShowing boolValue]) {
                  [weakSelf.vpnManager startVPN];
              }
          }
          error:^(NSError *error) {
              [weakSelf.compoundDisposable removeDisposable:disposable];
          }
          completed:^{
              [weakSelf.compoundDisposable removeDisposable:disposable];
          }];

        [self.compoundDisposable addDisposable:disposable];

    } else if ([NotifierAvailableEgressRegions isEqualToString:message]) {
        LOG_DEBUG(@"Received notification NE.onAvailableEgressRegions");
        // Update available regions
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray<NSString *> *regions = [weakSelf.sharedDB emittedEgressRegions];
            [[RegionAdapter sharedInstance] onAvailableEgressRegions:regions];
        });

    } else if ([NotifierMarkedAuthorizations isEqualToString:message]) {
        [[PsiCashClient sharedInstance] authorizationsMarkedExpired];

    } else if ([NotifierNetworkConnectivityFailed isEqualToString:message]) {
        [self.checkExtensionNetworkConnectivityFailedSubject sendNext:RACUnit.defaultUnit];
    }
}

#pragma mark - Subscription

- (void)subscriptionExpiryTimer {

    __weak AppDelegate *weakSelf = self;

    NSDate *expiryDate;
    BOOL activeSubscription = [IAPStoreHelper hasActiveSubscriptionForDate:[NSDate date] getExpiryDate:&expiryDate];

    if (activeSubscription) {

        // Also update the subscription status subject.
        [weakSelf.subscriptionStatus sendNext:@(UserSubscriptionActive)];

        NSTimeInterval interval = [expiryDate timeIntervalSinceNow];

        if (interval > 0) {
            // Checks if another timer is already running.
            if (![weakSelf.subscriptionCheckTimer isValid]) {
                weakSelf.subscriptionCheckTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                                         repeats:NO
                                                                           block:^(NSTimer *timer) {
                    [weakSelf subscriptionExpiryTimer];
                }];
            }
        }
    } else {
        [self.subscriptionStatus sendNext:@(UserSubscriptionInactive)];
    }
}

- (void)onSubscriptionActivated {

    __weak AppDelegate *weakSelf = self;

    [self.subscriptionStatus sendNext:@(UserSubscriptionActive)];

    [self subscriptionExpiryTimer];

    // Asks the extension to perform a subscription check if it is running currently.
    __block RACDisposable *vpnActiveDisposable = [[self.vpnManager isVPNActive]
      subscribeNext:^(RACTwoTuple<NSNumber *, NSNumber *> *value) {
        BOOL isActive = [value.first boolValue];

        if (isActive) {
            [[Notifier sharedInstance] post:NotifierForceSubscriptionCheck];
        }

    } error:^(NSError *error) {
        [weakSelf.compoundDisposable removeDisposable:vpnActiveDisposable];
    } completed:^{
        [weakSelf.compoundDisposable removeDisposable:vpnActiveDisposable];
    }];

    [self.compoundDisposable addDisposable:vpnActiveDisposable];

}

// Called on `IAPHelperUpdatedSubscriptionDictionaryNotification` notification.
- (void)onUpdatedSubscriptionDictionary {

    __weak AppDelegate *weakSelf = self;

    dispatch_async_global(^{

        BOOL isSubscribed = [IAPStoreHelper hasActiveSubscriptionForNow];

        dispatch_async_main(^{

            if (isSubscribed) {
                [weakSelf onSubscriptionActivated];

            }
        });
    });
}

#pragma mark - Global alerts

- (UIAlertController *)displayAlertNoInternet:(void (^_Nullable)(UIAlertAction *))handler {

    UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:NSLocalizedStringWithDefaultValue(@"NO_INTERNET", nil, [NSBundle mainBundle], @"No Internet Connection", @"Alert title informing user there is no internet connection")
                       message:NSLocalizedStringWithDefaultValue(@"TURN_ON_DATE", nil, [NSBundle mainBundle], @"Turn on cellular data or use Wi-Fi to access data.", @"Alert message informing user to turn on their cellular data or wifi to connect to the internet")
                preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
      actionWithTitle:NSLocalizedStringWithDefaultValue(@"OK_BUTTON", nil, [NSBundle mainBundle], @"OK", @"Alert OK Button")
                style:UIAlertActionStyleDefault
              handler:^(UIAlertAction *action) {
                  if (handler) {
                      handler(action);
                  }
              }];

    [alert addAction:defaultAction];

    [alert presentFromTopController];

    return alert;
}

#pragma mark -

+ (UIViewController *)getTopMostViewController {
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;
    while(topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    return topController;
}

#pragma mark - Private helper methods

- (RACDisposable *)observeNetworkExtensionReachabilityStatus {
    AppDelegate *__weak weakSelf = self;

    __block UIAlertController *noInternetAlert;
    __block _Atomic BOOL ongoing;
    atomic_init(&ongoing, FALSE);

    return [[[[self.checkExtensionNetworkConnectivityFailedSubject
      filter:^BOOL(RACUnit *x) {
          // Prevent creation of another alert if one is already ongoing.
          return !atomic_load(&ongoing);
      }]
      flattenMap:^RACSignal<NSNumber *> *(RACUnit *x) {
          atomic_store(&ongoing, TRUE);

          // resolvedSignal is a hot terminating signal that emits @(TRUE) followed
          // by RACUnit if the extension posts that connectivity has been resolved
          // or that tunnel status changes to connected.
          RACSignal *resolvedSignal = [[[[[[Notifier sharedInstance]
            listenForMessages:@[NotifierNetworkConnectivityResolved]]
            merge:[weakSelf.vpnManager.lastTunnelStatus filter:^BOOL(NSNumber *v) {
                // Assumed resolved if VPN is connected, or not running.
                VPNStatus s = (VPNStatus) [v integerValue];
                return (s == VPNStatusConnected || s == VPNStatusDisconnected);
            }]]
            mapReplace:@(TRUE)]
            take:1]
            concat:[RACSignal return:RACUnit.defaultUnit]];

          // timerSignal is a cold terminating signal.
          RACSignal *timerSignal = [[[RACSignal timer:InternetReachabilityCheckTimeout]
            doNext:^(id x) {
                // Reset ongoing flag.
                atomic_store(&ongoing, FALSE);
            }]
            flattenMap:^RACSignal<NSNumber *> *(id x) {
                // Timer done. We now check extension internet reachability.
                return [weakSelf.vpnManager queryIsNetworkReachable];
            }];

          // The returned signal is a hot terminating signal that in effect unsubscribes
          // from the merged sources once `resolvedSignal` emits RACUnit.
          return [[[RACSignal merge:@[timerSignal, resolvedSignal]]
            takeUntilBlock:^BOOL(id emission) {
                return RACUnit.defaultUnit == emission;
            }]
            doCompleted:^{
                // Reset ongoing flag in case timer was cancelled by the resolvedSignal.
                atomic_store(&ongoing, FALSE);
            }];
      }]
      deliverOnMainThread]
      subscribeNext:^(NSNumber *_Nullable networkReachability) {
          // networkReachability is nil whenever VPNManager `-queryIsNetworkReachable` emits nil.

          if (![networkReachability boolValue]) {
              if (!noInternetAlert) {
                  noInternetAlert = [weakSelf displayAlertNoInternet:^(UIAlertAction *action) {
                      // Alert dismissed by user.
                      noInternetAlert = nil;
                  }];
              }
          } else {
              [noInternetAlert dismissViewControllerAnimated:TRUE completion:nil];
              noInternetAlert = nil;
          }

      }];
}

@end
