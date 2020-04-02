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
#import "AppObservables.h"
#import "Psiphon-Swift.h"


// Number of seconds to wait before checking reachability status after receiving
// `NotifierNetworkConnectivityFailed` from the extension.
NSTimeInterval const InternetReachabilityCheckTimeout = 10.0;

PsiFeedbackLogType const LandingPageLogType = @"LandingPage";
PsiFeedbackLogType const RewardedVideoLogType = @"RewardedVideo";


@interface AppDelegate () <NotifierObserver>

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
    RACDisposable *_Nullable rewardedVideoAdDisposable;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _vpnManager = [VPNManager sharedInstance];
        _sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];

        _checkExtensionNetworkConnectivityFailedSubject = [RACSubject subject];

    }
    return self;
}

- (void)dealloc {
    [self->rewardedVideoAdDisposable dispose];
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

    // Immediately register to receive notifications from the Network Extension process.
    [[Notifier sharedInstance] registerObserver:self callbackQueue:dispatch_get_main_queue()];

    // Initializes PsiphonClientCommonLibrary.
    [PsiphonClientCommonLibraryHelpers initializeDefaultsForPlistsFromRoot:@"Root.inApp"];

    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    LOG_DEBUG();
    AppDelegate *__weak weakSelf = self;

    [AppObservables.shared appLaunched];

    [SwiftDelegate.bridge applicationDidFinishLaunching:application
                                             objcBridge:(id<ObjCBridgeDelegate>) self];

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
            [SwiftDelegate.bridge resetLandingPage];
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
    __block RACDisposable *connectedDisposable =
    [[[RACSignal
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
    }] subscribeNext:^(RACUnit *x) {
        [weakSelf.vpnManager startVPN];
    } error:^(NSError *error) {
        [weakSelf.compoundDisposable removeDisposable:connectedDisposable];
    } completed:^{
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
    [SwiftDelegate.bridge applicationWillEnterForeground:application];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    LOG_DEBUG();
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    [SwiftDelegate.bridge applicationWillTerminate:application];
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
        [SwiftDelegate.bridge showLandingPage];


    } else if ([NotifierTunnelConnected isEqualToString:message]) {
        LOG_DEBUG(@"Received notification NE.tunnelConnected");

        // If we haven't had a chance to load an Ad, and the
        // tunnel is already connected, give up on the Ad and
        // start the VPN. Otherwise the startVPN message will be
        // sent after the Ad has disappeared.
        __block RACDisposable *disposable =
        [[[AdManager sharedInstance].adIsShowing take:1]
         subscribeNext:^(NSNumber *adIsShowing) {
            if (![adIsShowing boolValue]) {
                [weakSelf.vpnManager startVPN];
            }
        } error:^(NSError *error) {
            [weakSelf.compoundDisposable removeDisposable:disposable];
        } completed:^{
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

    } else if ([NotifierNetworkConnectivityFailed isEqualToString:message]) {
        [self.checkExtensionNetworkConnectivityFailedSubject sendNext:RACUnit.defaultUnit];
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

@end

#pragma mark - ObjCBridgeDelegate

@interface UIViewController (DimissViewController)
// Helper function for dismissing a ViewController in the hierarchy.
- (void)dismissViewControllerType:(Class)viewControllerClass;
@end

@implementation UIViewController (DismissViewController)

- (void)dismissViewControllerType:(Class)viewControllerClass {
    if ([self isKindOfClass:viewControllerClass]) {
        [self dismissViewControllerAnimated:true completion:nil];
        return;
    }

    for (UIViewController *childVC in self.childViewControllers) {
        [childVC dismissViewControllerType:viewControllerClass];
    }

    [self.presentedViewController dismissViewControllerType:viewControllerClass];
}

@end

@interface AppDelegate (SwiftExtensions) <ObjCBridgeDelegate>
@end

@implementation AppDelegate (SwiftExtensions)

- (void)onPsiCashBalanceUpdate:(BridgedBalanceViewBindingType *)balance {
    [AppObservables.shared.psiCashBalance sendNext:balance];
}

- (void)onSpeedBoostActivePurchase:(NSDate *)expiryTime {
    [AppObservables.shared.speedBoostExpiry sendNext:expiryTime];
}

- (void)onSubscriptionStatus:(BridgedUserSubscription * _Nonnull)status {
    [AppObservables.shared.subscriptionStatus sendNext:status];
}

- (void)dismissWithScreen:(enum DismissableScreen)screen {
    switch (screen) {
        case DismissableScreenPsiCash:
            [self.window.rootViewController dismissViewControllerType:PsiCashViewController.class];
            break;
    }
}

- (void)presentRewardedVideoAdWithCustomData:(NSString *)customData
                                    delegate:(id<RewardedVideoAdBridgeDelegate>)delegate {
    // No-op if there's an active subscription for displaying rewarded videos.
    if (self->rewardedVideoAdDisposable) {
        return;
    }

    AppDelegate *__weak weakSelf = self;

    // If the current view controller at the time of this call is not present,
    // we will not display the ad.
    // This is to guarantee to a degree that current VC that was the origin of this
    // function call is still present by the time the ad is loaded and ready to be presented.
    // Note that the guarantee is strong only if `weakTopMostVC.beingDismissed` flag is checked
    // immediately before presenting.
    UIViewController *__weak weakTopMostVC = [AppDelegate getTopMostViewController];

    LOG_DEBUG(@"rewarded video started");

    self->rewardedVideoAdDisposable =
    [[[[[[[[[[[AdManager sharedInstance].rewardedVideoLoadStatus
             scanWithStart:nil reduce:^id(NSNumber *_Nullable running, NSNumber *next) {

        // If the observable chain starts with an error, force load an ad.
        // Pretend the load status is `AdLoadStatusInProgress` after force loading an ad.
        if (!running) {
            dispatch_async_main(^{
                [[AdManager sharedInstance].forceRewardedVideoLoad sendNext:RACUnit.defaultUnit];
            });
            return @(AdLoadStatusInProgress);
        }
        return next;
    }] doNext:^(NSNumber *adLoadStatusObj) {
        AdLoadStatus s = (AdLoadStatus) [adLoadStatusObj integerValue];
        [delegate adLoadStatus:s error:nil];
    }] filter:^BOOL(NSNumber *adLoadStatusObj) {
        AdLoadStatus s = (AdLoadStatus) [adLoadStatusObj integerValue];
        // Filter terminating states.
        return (AdLoadStatusDone == s) || (AdLoadStatusError == s);
    }] take:1]
          flattenMap:^RACSignal *(NSNumber *adLoadStatusObj) {
        UIViewController *__strong topMostVC = weakTopMostVC;
        AdLoadStatus s = (AdLoadStatus) [adLoadStatusObj integerValue];

        if (topMostVC && !topMostVC.beingDismissed && AdLoadStatusDone == s) {
            return [[AdManager sharedInstance] presentRewardedVideoOnViewController:topMostVC withCustomData:customData];
        } else {
            return [RACSignal empty];
        }
    }] doNext:^(NSNumber *adPresentationEnum) {
        // Logs current AdPresentation enum value.
        AdPresentation ap = (AdPresentation) [adPresentationEnum integerValue];
        [delegate adPresentationStatus:ap];
        switch (ap) {
            case AdPresentationWillAppear:
                [PsiFeedbackLogger infoWithType:RewardedVideoLogType format:@"AdPresentationWillAppear"];
                LOG_DEBUG(@"rewarded video AdPresentationWillAppear");
                break;
            case AdPresentationDidAppear:
                LOG_DEBUG(@"rewarded video AdPresentationDidAppear");
                break;
            case AdPresentationWillDisappear:
                LOG_DEBUG(@"rewarded video AdPresentationWillDisappear");
                break;
            case AdPresentationDidDisappear:
                LOG_DEBUG(@"rewarded video AdPresentationDidDisappear");
                break;
            case AdPresentationDidRewardUser:
                LOG_DEBUG(@"rewarded video AdPresentationDidRewardUser");
                break;
            case AdPresentationErrorCustomDataNotSet:
                LOG_DEBUG(@"rewarded video AdPresentationErrorCustomDataNotSet");
                [PsiFeedbackLogger errorWithType:RewardedVideoLogType
                                         format:@"AdPresentationErrorCustomDataNotSet"];
                break;
            case AdPresentationErrorInappropriateState:
                LOG_DEBUG(@"rewarded video AdPresentationErrorInappropriateState");
                [PsiFeedbackLogger errorWithType:RewardedVideoLogType
                                         format:@"AdPresentationErrorInappropriateState"];
                break;
            case AdPresentationErrorNoAdsLoaded:
                LOG_DEBUG(@"rewarded video AdPresentationErrorNoAdsLoaded");
                [PsiFeedbackLogger errorWithType:RewardedVideoLogType
                                         format:@"AdPresentationErrorNoAdsLoaded"];
                break;
            case AdPresentationErrorFailedToPlay:
                LOG_DEBUG(@"rewarded video AdPresentationErrorFailedToPlay");
                [PsiFeedbackLogger errorWithType:RewardedVideoLogType
                                         format:@"AdPresentationErrorFailedToPlay"];
                break;
        }
    }] scanWithStart:[RACTwoTuple pack:@(FALSE) :@(FALSE)]
        reduce:^RACTwoTuple<NSNumber *, NSNumber *> *(RACTwoTuple *running,
                                                      NSNumber *adPresentationEnum) {

        // Scan operator's `running` value is a 2-tuple of booleans. First element represents when
        // AdPresentationDidRewardUser is emitted upstream, and the second element represents when
        // AdPresentationDidDisappear is emitted upstream.
        // Note that we don't want to make any assumptions about the order of these two events.
        if ([adPresentationEnum integerValue] == AdPresentationDidRewardUser) {
            return [RACTwoTuple pack:@(TRUE) :running.second];
        } else if ([adPresentationEnum integerValue] == AdPresentationDidDisappear) {
            return [RACTwoTuple pack:running.first :@(TRUE)];
        }
        return running;
    }] filter:^BOOL(RACTwoTuple<NSNumber *, NSNumber *> *tuple) {
        // We will always end the stream if ad did disappear.
        // TODO: This assumes that didReward event is sent before didDisappear.
        BOOL didDisappear = [tuple.second boolValue];
        return didDisappear;
    }] take:1]
     subscribeNext:^(RACTwoTuple<NSNumber *, NSNumber *> *tuple) {
        // No-op.
    } error:^(NSError *error) {
        AppDelegate *strongSelf = weakSelf;
        if (strongSelf) {
            [delegate adLoadStatus:AdLoadStatusError error:error];
            [PsiFeedbackLogger errorWithType:RewardedVideoLogType message:@"Error with rewarded video"
                                      object:error];
            [strongSelf->rewardedVideoAdDisposable dispose];
            strongSelf->rewardedVideoAdDisposable = nil;
        }
    } completed:^{
        AppDelegate *strongSelf = weakSelf;
        if (strongSelf) {
            LOG_DEBUG(@"rewarded video completed");
            [PsiFeedbackLogger infoWithType:RewardedVideoLogType format:@"completed"];
            [strongSelf->rewardedVideoAdDisposable dispose];
            strongSelf->rewardedVideoAdDisposable = nil;
        }
    }];
}

@end
