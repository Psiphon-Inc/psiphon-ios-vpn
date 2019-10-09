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
#import <ReactiveObjC/RACUnit.h>
#import <ReactiveObjC/NSNotificationCenter+RACSupport.h>
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
#import "RACMulticastConnection.h"
#import "AppEvent.h"
#import "RACSignal.h"
#import "RACSignal+Operations2.h"
#import "NSError+Convenience.h"
#import "RACCompoundDisposable.h"
#import "RACSignal+Operations.h"
#import "RACReplaySubject.h"
#import "Asserts.h"
#import "ContainerDB.h"
#import "AppUpgrade.h"
#import "AppEvent.h"
#import "Psiphon-Swift.h"


// Number of seconds to wait before checking reachability status after receiving
// `NotifierNetworkConnectivityFailed` from the extension.
NSTimeInterval const InternetReachabilityCheckTimeout = 10.0;

PsiFeedbackLogType const LandingPageLogType = @"LandingPage";

@interface AppDelegate () <NotifierObserver, SwiftToObjBridge>

// Public properties

@property (nonatomic, nullable, readwrite) RACMulticastConnection<AppEvent *> *appEvents;

//// subscriptionStatus should only be sent events to from the main thread.
//// Emits type ObjcUserSubscription
@property (nonatomic, readwrite) RACReplaySubject<ObjcUserSubscription *> *subscriptionStatus;

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
    Reachability *reachability;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _subscriptionStatus = [RACReplaySubject replaySubjectWithCapacity:1];

        _vpnManager = [VPNManager sharedInstance];
        _sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];

        _checkExtensionNetworkConnectivityFailedSubject = [RACSubject subject];

        reachability = [Reachability reachabilityForInternetConnection];
    }
    return self;
}

- (void)dealloc {
    [reachability stopNotifier];
    [self.compoundDisposable dispose];
}

+ (AppDelegate *)sharedAppDelegate {
    return (AppDelegate *)[UIApplication sharedApplication].delegate;
}

# pragma mark - Lifecycle methods

- (BOOL)application:(UIApplication *)application
    willFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    if ([AppUpgrade firstRunOfAppVersion]) {
        [self updateAvailableEgressRegionsOnFirstRunOfAppVersion];

        // Reset Jetsam counter.
        [self.sharedDB resetJetsamCounter];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onUpdatedSubscriptionDictionary)
                                                 name:IAPHelperUpdatedSubscriptionDictionaryNotification
                                               object:nil];

    // Immediately register to receive notifications from the Network Extension process.
    [[Notifier sharedInstance] registerObserver:self callbackQueue:dispatch_get_main_queue()];

    // Initializes PsiphonClientCommonLibrary.
    [PsiphonClientCommonLibraryHelpers initializeDefaultsForPlistsFromRoot:@"Root.inApp"];


    [[IAPStoreHelper sharedInstance] startProductsRequest];

    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    LOG_DEBUG();

    [SwiftAppDelegate.instance setWithBridge:self];

    __weak AppDelegate *weakSelf = self;

    // App events signal.
    {

        [reachability startNotifier];

        // Infinite hot signal - emits an item after the app delegate applicationWillEnterForeground: is called.
        RACSignal *appWillEnterForegroundSignal = [[NSNotificationCenter defaultCenter]
                                                                         rac_addObserverForName:UIApplicationWillEnterForegroundNotification object:nil];

        // Infinite cold signal - emits @(TRUE) when network is reachable, @(FALSE) otherwise.
        // Once subscribed to, starts with the current network reachability status.
        //
        RACSignal<NSNumber *> *reachabilitySignal = [[[[[NSNotificationCenter defaultCenter]
                                                                              rac_addObserverForName:kReachabilityChangedNotification object:reachability]
                                                                              map:^NSNumber *(NSNotification *note) {
                                                                                  return @(((Reachability *) note.object).currentReachabilityStatus);
                                                                              }]
                                                                              startWith:@([reachability currentReachabilityStatus])]
                                                                              map:^NSNumber *(NSNumber *value) {
                                                                                  NetworkStatus s = (NetworkStatus) [value integerValue];
                                                                                  return @(s != NotReachable);
                                                                              }];

        // Infinite cold signal - emits @(TRUE) if user has an active subscription, @(FALSE) otherwise.
        // Note: Nothing is emitted if the subscription status is unknown.
        RACSignal<NSNumber *> *activeSubscriptionSignal = [[[AppDelegate sharedAppDelegate].subscriptionStatus
          filter:^BOOL(ObjcUserSubscription *status) {
            return status.state != ObjcSubscriptionStateUnknown;
          }]
          map:^NSNumber *(ObjcUserSubscription *status) {
              return @(status.state == ObjcSubscriptionStateActive);
          }];

        // Infinite cold signal - emits events of type @(TunnelState) for various tunnel events.
        // While the tunnel is being established or destroyed, this signal emits @(TunnelStateNeither).
        RACSignal<NSNumber *> *tunnelConnectedSignal = [[VPNManager sharedInstance].lastTunnelStatus
          map:^NSNumber *(NSNumber *value) {
              VPNStatus s = (VPNStatus) [value integerValue];

              if (s == VPNStatusConnected) {
                  return @(TunnelStateTunneled);
              } else if (s == VPNStatusDisconnected || s == VPNStatusInvalid) {
                  return @(TunnelStateUntunneled);
              } else {
                  return @(TunnelStateNeither);
              }
          }];

        // NOTE: We have to be careful that ads are requested,
        //       loaded and the impression is registered all from the same tunneled/untunneled state.

        // combinedEventSignal is infinite cold signal - Combines all app event signals,
        // and create AppEvent object. The AppEvent emissions are as unique as `[AppEvent isEqual:]` determines.
        RACSignal<AppEvent *> *combinedEventSignals = [[[RACSignal
          combineLatest:@[
            reachabilitySignal,
            activeSubscriptionSignal,
            tunnelConnectedSignal
          ]]
          map:^AppEvent *(RACTuple *eventsTuple) {

              AppEvent *e = [[AppEvent alloc] init];
              e.networkIsReachable = [((NSNumber *) eventsTuple.first) boolValue];
              e.subscriptionIsActive = [((NSNumber *) eventsTuple.second) boolValue];
              e.tunnelState = (TunnelState) [((NSNumber *) eventsTuple.third) integerValue];
              return e;
          }]
          distinctUntilChanged];

        // The underlying multicast signal emits AppEvent objects. The emissions are repeated if a "trigger" event
        // such as "appWillForeground" happens with source set to appropriate value.
        self.appEvents = [[[[RACSignal
          // Merge all "trigger" signals that cause the last AppEvent from `combinedEventSignals` to be emitted again.
          // NOTE: - It should be guaranteed that SourceEventStarted is always the first emission and that it will
          //         be always after the Ad SDKs have been initialized.
          //       - It should also be guaranteed that signals in the merge below are not the same as the signals
          //         in the `combinedEventSignals`. Otherwise we would have subscribed to the same signal twice,
          //         and since we're using the -combineLatestWith: operator, we will get the same emission repeated.
          merge:@[
            [RACSignal return:@(SourceEventStarted)],
            [appWillEnterForegroundSignal mapReplace:@(SourceEventAppForegrounded)]
          ]]
          combineLatestWith:combinedEventSignals]
          combinePreviousWithStart:nil reduce:^AppEvent *(RACTwoTuple<NSNumber *, AppEvent *> *_Nullable prev,
            RACTwoTuple<NSNumber *, AppEvent *> *_Nonnull curr) {

              // Infers the source signal of the current emission.
              //
              // Events emitted by the signal that we combine with (`combinedEventSignals`) are unique,
              // and therefore the AppEvent state that is different between `prev` and `curr` is also the source.
              // If `prev` and `curr` AppEvent are the same, then the "trigger" signal is one of the merged signals
              // upstream.

              AppEvent *_Nullable pe = prev.second;
              AppEvent *_Nonnull ce = curr.second;

              if (pe == nil || [pe isEqual:ce]) {
                  // Event source is not from the change in AppEvent properties and so not from `combinedEventSignals`.
                  ce.source = (SourceEvent) [curr.first integerValue];
              } else {

                  // Infer event source based on changes in values.
                  if (pe.networkIsReachable != ce.networkIsReachable) {
                      ce.source = SourceEventReachability;

                  } else if (pe.subscriptionIsActive != ce.subscriptionIsActive) {
                      ce.source = SourceEventSubscription;

                  } else if (pe.tunnelState != ce.tunnelState) {
                      ce.source = SourceEventTunneled;
                  }
              }

              return ce;
          }]
          multicast:[RACReplaySubject replaySubjectWithCapacity:1]];

#if DEBUG
        [self.compoundDisposable addDisposable:[self.appEvents.signal subscribeNext:^(AppEvent * _Nullable x) {
            LOG_DEBUG(@"\n%@", [x debugDescription]);
        }]];
#endif

        [self.compoundDisposable addDisposable:[[AppDelegate sharedAppDelegate].appEvents connect]];

        [SwiftAppDelegate.instance setWithVpnManager:VPNManager.sharedInstance];
        [SwiftAppDelegate.instance applicationDidFinishLaunching:application];
    }

    // Override point for customization after application launch.
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    rootContainerController = [[RootContainerController alloc] init];
    self.window.rootViewController = rootContainerController;

    // UIKit always waits for application:didFinishLaunchingWithOptions:
    // to return before making the window visible on the screen.
    [self.window makeKeyAndVisible];

    // Listen for VPN status changes from VPNManager.
    __block RACDisposable *disposable = [self.vpnManager.lastTunnelStatus
      subscribeNext:^(NSNumber *statusObject) {
          VPNStatus s = (VPNStatus) [statusObject integerValue];

          if (s == VPNStatusDisconnected || s == VPNStatusRestarting ) {
              // Resets the homepage flag if the VPN has disconnected or is restarting.
              [SwiftAppDelegate.instance resetLandingPage];
          }

      } error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:disposable];
      } completed:^{
          [weakSelf.compoundDisposable removeDisposable:disposable];
      }];

    [self.compoundDisposable addDisposable:disposable];

    // Observe internet reachability status.
    [self.compoundDisposable addDisposable:[self observeNetworkExtensionReachabilityStatus]];

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    LOG_DEBUG();

    __weak AppDelegate *weakSelf = self;

    // TODO! initialize the SubscriptionActor when it first starts
    // Starts subscription expiry timer if there is an active subscription.
//    [self subscriptionExpiryTimer];

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

    // TODO!!
//     Resets status of the subjects whose state could be stale once the container is foregrounded.
//    [self.subscriptionStatus sendNext:@(UserSubscriptionUnknown)];

    [SwiftAppDelegate.instance applicationWillEnterForeground:application];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    LOG_DEBUG();
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

#pragma mark -

- (void)reloadMainViewControllerAndImmediatelyOpenSettings {
    LOG_DEBUG();
    [rootContainerController reloadMainViewControllerAndImmediatelyOpenSettings];
}

- (void)reloadOnboardingViewController {
    LOG_DEBUG();
    [rootContainerController reloadOnboardingViewController];
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
        [[[ContainerDB alloc] init] setEmbeddedEgressRegions:embeddedEgressRegions];
    } else {
        [PsiFeedbackLogger error:@"Error no egress regions found in %@.", embeddedServerEntriesPath];
    }
}

#pragma mark - Notifier callback

- (void)onMessageReceived:(NotifierMessage)message {

    __weak AppDelegate *weakSelf = self;

    if ([NotifierNewHomepages isEqualToString:message]) {

        LOG_DEBUG(@"Received notification NE.newHomepages");
        [SwiftAppDelegate.instance showLandingPage];


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
        // TODO! PsiCash: tell psicash of authorizations marked as expired.
//        [[PsiCashClient sharedInstance] authorizationsMarkedExpired];

    } else if ([NotifierNetworkConnectivityFailed isEqualToString:message]) {
        [self.checkExtensionNetworkConnectivityFailedSubject sendNext:RACUnit.defaultUnit];
    }
}

#pragma mark - Subscription


// Called on `IAPHelperUpdatedSubscriptionDictionaryNotification` notification.
- (void)onUpdatedSubscriptionDictionary {

    NSDictionary *_Nullable subscription = IAPStoreHelper.subscriptionDictionary;

    if (subscription) {
        // TODO! send message to SubscriptionActor
    }

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

- (void)onSubscriptionStatus:(ObjcUserSubscription *)status {
    [self.subscriptionStatus sendNext:status];
}

@end
