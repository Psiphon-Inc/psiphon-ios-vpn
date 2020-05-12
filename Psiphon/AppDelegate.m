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
#import "Notifier.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "PsiphonConfigReader.h"
#import "PsiphonDataSharedDB.h"
#import "RootContainerController.h"
#import "SharedConstants.h"
#import "UIAlertController+Additions.h"
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
#import <PsiphonTunnel/PsiphonTunnel.h>

PsiFeedbackLogType const LandingPageLogType = @"LandingPage";
PsiFeedbackLogType const RewardedVideoLogType = @"RewardedVideo";


@interface AppDelegate () <NotifierObserver>

// Private properties
@property (nonatomic) RACCompoundDisposable *compoundDisposable;
@property (nonatomic) PsiphonDataSharedDB *sharedDB;

@end

@implementation AppDelegate {
    BOOL pendingStartStopSignalCompletion;
    RootContainerController *rootContainerController;
    RACDisposable *_Nullable rewardedVideoAdDisposable;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        pendingStartStopSignalCompletion = FALSE;
        _sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
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
    
    // Forwards AdManager `adIsShowing` events to SwiftDelegate.
    [self.compoundDisposable addDisposable:[[AdManager sharedInstance].adIsShowing subscribeNext:^(NSNumber * _Nullable adisShowingObj) {
        [SwiftDelegate.bridge onAdPresentationStatusChange: [adisShowingObj boolValue]];
    }]];
    
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    LOG_DEBUG();
    
    [SwiftDelegate.bridge applicationDidBecomeActive:application];

    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
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

#pragma mark - VPN start stop

typedef NS_ENUM(NSInteger, VPNIntent) {
    VPNIntentStartPsiphonTunnelWithoutAds,
    VPNIntentStartPsiphonTunnelWithAds,
    VPNIntentStopVPN,
    VPNIntentNoInternetAlert,
};

// Emitted NSNumber is of type VPNIntent.
- (RACSignal<RACTwoTuple<NSNumber*, SwitchedVPNStartStopIntent*> *> *)startOrStopVPNSignalWithAd:(BOOL)showAd {
    
    return [[[[RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {
        [[SwiftDelegate.bridge swithVPNStartStopIntent]
         then:^id _Nullable(SwitchedVPNStartStopIntent * newIntent) {
            if (newIntent == nil) {
                [NSException raise:@"nil found"
                            format:@"expected non-nil SwitchedVPNStartStopIntent value"];
            }
            
            VPNIntent vpnIntentValue;
            
            if (newIntent.intendToStart) {
                // If the new intent is to start the VPN, first checks for internet connectivity.
                // If there is internet connectivity, tunnel can be startet without ads
                // if the user is subscribed, if if there the VPN config is not installed.
                // Otherwise tunnel should be started after interstitial ad has been displayed.
                
                Reachability *reachability = [Reachability reachabilityForInternetConnection];
                if ([reachability currentReachabilityStatus] == NotReachable) {
                    vpnIntentValue = VPNIntentNoInternetAlert;
                } else {
                    if (newIntent.vpnConfigInstalled) {
                        if (newIntent.userSubscribed || !showAd) {
                            vpnIntentValue = VPNIntentStartPsiphonTunnelWithoutAds;
                        } else {
                            vpnIntentValue = VPNIntentStartPsiphonTunnelWithAds;
                        }
                    } else {
                        // VPN Config is not installed. Skip ads.
                        vpnIntentValue = VPNIntentStartPsiphonTunnelWithoutAds;
                    }
                }
            } else {
                // The new intent is to stop the VPN.
                vpnIntentValue = VPNIntentStopVPN;
            }
            
            [subscriber sendNext:[RACTwoTuple pack:@(vpnIntentValue) :newIntent]];
            [subscriber sendCompleted];
            return nil;
        }];
        
        return nil;
    }] flattenMap:^RACSignal<RACTwoTuple *> *(RACTwoTuple<NSNumber*, SwitchedVPNStartStopIntent*> *value) {
        VPNIntent vpnIntent = (VPNIntent)[value.first integerValue];
        if (vpnIntent == VPNIntentStartPsiphonTunnelWithAds) {
            // Start tunnel after ad presentation signal completes.
            // We always want to start the tunnel after the presentation signal
            // is completed, no matter if it presented an ad or it failed.
            return [[AdManager.sharedInstance
                     presentInterstitialOnViewController:[AppDelegate getTopMostViewController]]
                    then:^RACSignal * {
                return [RACSignal return:value];
            }];
        } else {
            return [RACSignal return:value];
        }
    }] doNext:^(RACTwoTuple<NSNumber*, SwitchedVPNStartStopIntent*> *value) {
        VPNIntent vpnIntent = (VPNIntent)[value.first integerValue];
        dispatch_async_main(^{
            [SwiftDelegate.bridge sendNewVPNIntent:value.second];

            if (vpnIntent == VPNIntentNoInternetAlert) {
                // TODO: Show the no internet alert.
            }
        });
    }] deliverOnMainThread];
}

- (void)startStopVPNWithAd:(BOOL)showAd {
    AppDelegate *__weak weakSelf = self;
    
    if (pendingStartStopSignalCompletion == TRUE) {
        return;
    }
    pendingStartStopSignalCompletion = TRUE;

    __block RACDisposable *disposable = [[self startOrStopVPNSignalWithAd:showAd]
      subscribeError:^(NSError *error) {
        [weakSelf.compoundDisposable removeDisposable:disposable];
      }
      completed:^{
        if (NSThread.isMainThread != TRUE) {
            [NSException raise:@"MainThreadCheck"
                        format:@"Expected callback on main-thread"];
        }
        AppDelegate *__strong strongSelf = weakSelf;
        if (strongSelf != nil) {
            [strongSelf.compoundDisposable removeDisposable:disposable];
            strongSelf->pendingStartStopSignalCompletion = FALSE;
        }
      }];

    [self.compoundDisposable addDisposable:disposable];
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
    if ([NotifierTunnelConnected isEqualToString:message]) {
        LOG_DEBUG(@"Received notification NE.tunnelConnected");
        [SwiftDelegate.bridge syncWithTunnelProviderWithReason:
         TunnelProviderSyncReasonProviderNotificationPsiphonTunnelConnected];

    } else if ([NotifierAvailableEgressRegions isEqualToString:message]) {
        LOG_DEBUG(@"Received notification NE.onAvailableEgressRegions");
        // Update available regions
        __weak AppDelegate *weakSelf = self;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray<NSString *> *regions = [weakSelf.sharedDB emittedEgressRegions];
            [[RegionAdapter sharedInstance] onAvailableEgressRegions:regions];
        });

    } else if ([NotifierNetworkConnectivityFailed isEqualToString:message]) {
        // TODO: fix
    }
}

#pragma mark -

+ (UIViewController *)getTopMostViewController {
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;
    while(topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    return topController;
}

@end

#pragma mark - ObjCBridgeDelegate

@interface UIViewController (DimissViewController)
// Helper function for dismissing a ViewController in the hierarchy.
- (void)dismissViewControllerType:(Class)viewControllerClass
                       completion:(void (^ _Nullable)(void))completion;
@end

@implementation UIViewController (DismissViewController)

- (void)dismissViewControllerType:(Class)viewControllerClass
                       completion:(void (^ _Nullable)(void))completion
{
    if ([self isKindOfClass:viewControllerClass]) {
        [self dismissViewControllerAnimated:true completion:completion];
        return;
    }

    for (UIViewController *childVC in self.childViewControllers) {
        [childVC dismissViewControllerType:viewControllerClass completion:completion];
    }

    [self.presentedViewController dismissViewControllerType:viewControllerClass
                                                 completion:completion];
}

@end

@interface AppDelegate (SwiftExtensions) <ObjCBridgeDelegate>
@end

@implementation AppDelegate (SwiftExtensions)

- (void)startStopVPNWithInterstitial {
    [self startStopVPNWithAd:TRUE];
}

- (void)onPsiCashBalanceUpdate:(BridgedBalanceViewBindingType *)balance {
    [AppObservables.shared.psiCashBalance sendNext:balance];
}

- (void)onSpeedBoostActivePurchase:(NSDate *)expiryTime {
    [AppObservables.shared.speedBoostExpiry sendNext:expiryTime];
}

- (void)onSubscriptionStatus:(BridgedUserSubscription * _Nonnull)status {
    [AppObservables.shared.subscriptionStatus sendNext:status];
}

- (void)onVPNStatusDidChange:(NEVPNStatus)status {
    [AppObservables.shared.vpnStatus sendNext:@(status)];
}

- (void)onVPNStateSyncError:(NSString *)userErrorMessage {
    UIAlertController *ac = [UIAlertController
                             alertControllerWithTitle:[UserStrings Error_title]
                             message:userErrorMessage
                             preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:[UserStrings OK_button_title]
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil];
    
    UIAlertAction *reinstallConfigAction = [UIAlertAction
                                            actionWithTitle:[UserStrings Reinstall_vpn_config]
                                            style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [SwiftDelegate.bridge reinstallVPNConfig];
    }];
    [ac addAction:okAction];
    [ac addAction:reinstallConfigAction];
    [ac presentFromTopController];
}

- (void)onVPNStartStopStateDidChange:(VPNStartStopStatus)status {
    [AppObservables.shared.vpnStartStopStatus sendNext:@(status)];
}

- (void)dismissWithScreen:(enum DismissibleScreen)screen
               completion:(void (^ _Nullable)(void))completion
{
    switch (screen) {
        case DismissibleScreenPsiCash:
            [self.window.rootViewController dismissViewControllerType:PsiCashViewController.class
                                                           completion:completion];
            break;
    }
}

- (void)presentUntunneledRewardedVideoAdWithCustomData:(NSString *)customData
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
