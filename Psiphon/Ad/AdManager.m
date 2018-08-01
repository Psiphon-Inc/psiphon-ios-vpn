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

#import <PsiphonTunnel/PsiphonTunnel.h>
#import "AdManager.h"
#import "VPNManager.h"
#import "AppDelegate.h"
#import "Logging.h"
#import "IAPStoreHelper.h"
#import "RACCompoundDisposable.h"
#import "RACSignal.h"
#import "RACSignal+Operations.h"
#import "RACReplaySubject.h"
#import "DispatchUtils.h"
#import "MPGoogleGlobalMediationSettings.h"
#import "InterstitialAdControllerWrapper.h"
#import "RewardedAdControllerWrapper.h"
#import <ReactiveObjC/NSNotificationCenter+RACSupport.h>
#import <ReactiveObjC/RACUnit.h>
#import <ReactiveObjC/RACTuple.h>
#import <ReactiveObjC/NSObject+RACPropertySubscribing.h>
#import <ReactiveObjC/RACMulticastConnection.h>
#import <ReactiveObjC/RACGroupedSignal.h>
#import <ReactiveObjC/RACScheduler.h>
#import "RACSubscriptingAssignmentTrampoline.h"
#import "RACSignal+Operations2.h"
#import "Asserts.h"
#import "NSError+Convenience.h"
@import GoogleMobileAds;


NSErrorDomain const AdControllerWrapperErrorDomain = @"AdControllerWrapperErrorDomain";

PsiFeedbackLogType const AdManagerLogType = @"AdManager";

#pragma mark - Ad Unit IDs

NSString * const UntunneledInterstitialAdUnitID = @"4250ebf7b28043e08ddbe04d444d79e4";
NSString * const UntunneledRewardVideoAdUnitID  = @"00638d8c82b34f9e8fe56b51cc704c87";
NSString * const TunneledRewardVideoAdUnitID    = @"b9440504384740a2a3913a3d1b6db80e";

// AdControllerTag values must be unique.
AdControllerTag const AdControllerTagUntunneledInterstitial = @"UntunneledInterstitial";
AdControllerTag const AdControllerTagUntunneledRewardedVideo = @"UntunneledRewardedVideo";
AdControllerTag const AdControllerTagTunneledRewardedVideo = @"TunneledRewardedVideo";

#pragma mark - App event type

typedef NS_ENUM(NSInteger, TunnelState) {
    TunnelStateTunneled = 1,
    TunnelStateUntunneled,
    TunnelStateNeither
};

typedef NS_ENUM(NSInteger, SourceEvent) {
    SourceEventStarted = 100,
    SourceEventAppForegrounded = 101,
    SourceEventSubscription = 102,
    SourceEventTunneled = 103,
    SourceEventReachability = 104
};

@interface AppEvent : NSObject
// AppEvent source
@property (nonatomic, readwrite) SourceEvent source;

// AppEvent states
@property (nonatomic, readwrite) BOOL networkIsReachable;
@property (nonatomic, readwrite) BOOL subscriptionIsActive;
@property (nonatomic, readwrite) TunnelState tunnelState;
@end

@implementation AppEvent

// Two app events are equal only if all properties except the `source` are equal.
- (BOOL)isEqual:(AppEvent *)other {
    if (other == self)
        return TRUE;
    if (!other || ![[other class] isEqual:[self class]])
        return FALSE;
    return (self.networkIsReachable == other.networkIsReachable &&
            self.subscriptionIsActive == other.subscriptionIsActive &&
            self.tunnelState == other.tunnelState);
}

- (NSString *)debugDescription {

    NSString *sourceText;
    switch (self.source) {
        case SourceEventAppForegrounded:
            sourceText = @"SourceEventAppForegrounded";
            break;
        case SourceEventSubscription:
            sourceText = @"SourceEventSubscription";
            break;
        case SourceEventTunneled:
            sourceText = @"SourceEventTunneled";
            break;
        case SourceEventStarted:
            sourceText = @"SourceEventStarted";
            break;
        case SourceEventReachability:
            sourceText = @"SourceEventReachability";
            break;
        default: abort();
    }

    NSString *tunnelStateText;
    switch (self.tunnelState) {
        case TunnelStateTunneled:
            tunnelStateText = @"TunnelStateTunneled";
            break;
        case TunnelStateUntunneled:
            tunnelStateText = @"TunnelStateUntunneled";
            break;
        case TunnelStateNeither:
            tunnelStateText = @"TunnelStateNeither";
            break;
        default: abort();
    }

    return [NSString stringWithFormat:@"<AppEvent source=%@ networkIsReachable=%@ subscriptionIsActive=%@ "
                                       "tunnelState=%@>", sourceText, NSStringFromBOOL(self.networkIsReachable),
        NSStringFromBOOL(self.subscriptionIsActive), tunnelStateText];
}

@end

#pragma mark - SourceAction type

typedef NS_ENUM(NSInteger, AdLoadAction) {
    AdLoadActionImmediate = 200,
    AdLoadActionDelayed,
    AdLoadActionUnload,
    AdLoadActionNone
};

@interface AppEventActionTuple : NSObject
/** Action to take for an ad. */
@property (nonatomic, readwrite, assign) AdLoadAction action;
/** App state under which this action should be taken. */
@property (nonatomic, readwrite, nonnull) AppEvent *actionCondition;
/** Stop taking this action if stop condition emits anything. */
@property (nonatomic, readwrite, nonnull) RACSignal *stopCondition;

// Keep ad controller tag for debugging purposes.
@property (nonatomic, readwrite, nonnull) AdControllerTag tag;

@end

@implementation AppEventActionTuple

- (NSString *)debugDescription {
    NSString *actionText;
    switch (self.action) {
        case AdLoadActionImmediate:
            actionText = @"AdLoadActionImmediate";
            break;
        case AdLoadActionDelayed:
            actionText = @"AdLoadActionDelayed";
            break;
        case AdLoadActionUnload:
            actionText = @"AdLoadActionUnload";
            break;
        case AdLoadActionNone:
            actionText = @"AdLoadActionNone";
            break;
    }
    
    return [NSString stringWithFormat:@"<AppEventActionTuple action=%@ actionCondition=%@ stopCondition=%p>",
                                      actionText, [self.actionCondition debugDescription], self.stopCondition];
}

@end


#pragma mark - Ad Manager class

@interface AdManager ()

@property (nonatomic, readwrite, nonnull) RACReplaySubject<NSNumber *> *adIsShowing;
@property (nonatomic, readwrite, assign) BOOL untunneledInterstitialIsReady;
@property (nonatomic, readwrite, assign) BOOL rewardedVideoIsReady;

// Private properties
@property (nonatomic, readwrite, nonnull) InterstitialAdControllerWrapper *untunneledInterstitial;
@property (nonatomic, readwrite, nonnull) RewardedAdControllerWrapper *untunneledRewardVideo;
@property (nonatomic, readwrite, nonnull) RewardedAdControllerWrapper *tunneledRewardVideo;

// appEvents is hot infinite multicasted signal with underlying replay subject.
@property (nonatomic, nullable) RACMulticastConnection<AppEvent *> *appEvents;

@property (nonatomic, nonnull) RACCompoundDisposable *compoundDisposable;

@property (nonatomic, nonnull) RACReplaySubject<RACUnit *> *mopubSDKInitialized;

@end

@implementation AdManager {
    Reachability *reachability;
}

- (instancetype)init {
    self = [super init];
    if (self) {

        _adIsShowing = [RACReplaySubject replaySubjectWithCapacity:1];

        _compoundDisposable = [RACCompoundDisposable compoundDisposable];

        _untunneledInterstitial = [[InterstitialAdControllerWrapper alloc]
          initWithAdUnitID:UntunneledInterstitialAdUnitID withTag:AdControllerTagUntunneledInterstitial];

        _untunneledRewardVideo = [[RewardedAdControllerWrapper alloc]
          initWithAdUnitID:UntunneledRewardVideoAdUnitID withTag:AdControllerTagUntunneledRewardedVideo];

        _tunneledRewardVideo = [[RewardedAdControllerWrapper alloc]
          initWithAdUnitID:TunneledRewardVideoAdUnitID withTag:AdControllerTagTunneledRewardedVideo];

        _mopubSDKInitialized = [RACReplaySubject replaySubjectWithCapacity:1];

        reachability = [Reachability reachabilityForInternetConnection];

    }
    return self;
}

- (void)dealloc {
    [reachability stopNotifier];
    [self.compoundDisposable dispose];
}

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

// This should be called only once during application at application load time
- (void)initializeAdManager {

    [reachability startNotifier];

    // Initializes the Ads SDKs.
    {
        // Implementation follows these guides:
        //  - https://developers.mopub.com/docs/ios/initialization/
        //  - https://developers.mopub.com/docs/mediation/networks/google/

        [GADMobileAds configureWithApplicationID:@"ca-app-pub-1072041961750291~2085686375"];

        MPGoogleGlobalMediationSettings *googleMediationSettings = [[MPGoogleGlobalMediationSettings alloc] init];

        // MPMoPubConfiguration should be instantiated with any valid ad unit ID from the app.
        MPMoPubConfiguration *sdkConfig = [[MPMoPubConfiguration alloc]
          initWithAdUnitIdForAppInitialization:UntunneledInterstitialAdUnitID];

        sdkConfig.globalMediationSettings = @[googleMediationSettings];

        [[MoPub sharedInstance] initializeSdkWithConfiguration:sdkConfig completion:^{
            LOG_DEBUG(@"MoPub SDK initialized");
            [self.mopubSDKInitialized sendNext:RACUnit.defaultUnit];
        }];
    }

    // Main signals and subscription.
    {
        // Infinite hot signal - emits an item after the app delegate applicationWillEnterForeground: is called.
        RACSignal *appWillEnterForegroundSignal = [[NSNotificationCenter defaultCenter]
          rac_addObserverForName:UIApplicationWillEnterForegroundNotification object:nil];

        // Infinite cold signal - emits @(TRUE) when network is reachable, @(FALSE) otherwise.
        // Once subscribed to, starts with the current network reachability status.
        //
        RACSignal<NSNumber *> *reachabilitySignal = [[[[[NSNotificationCenter defaultCenter]
          rac_addObserverForName:kReachabilityChangedNotification object:reachability]
          map:^NSNumber *(NSNotification *note) {
              //
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
          filter:^BOOL(NSNumber *value) {
              UserSubscriptionStatus s = (UserSubscriptionStatus) [value integerValue];
              return s != UserSubscriptionUnknown;
          }]
          map:^NSNumber *(NSNumber *value) {
              UserSubscriptionStatus s = (UserSubscriptionStatus) [value integerValue];
              return @(s == UserSubscriptionActive);
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

        // The underlying multicast signal emits AppEvent objects. The objects are not necessarily unique.
        self.appEvents = [[[[RACSignal
          // Merge all "trigger" signals that cause the last AppEvent from `combinedEventSignals` to be emitted again.
          // NOTE: - It should be guaranteed that SourceEventStarted is always the first emission and that it will
          //         be always after the Ad SDKs have been initialized.
          //       - It should also be guaranteed that signals in the merge below are not the same as the signals
          //         in the `combinedEventSignals`. Otherwise we would have subscribed to the same signal twice,
          //         and since we're using the -combineLatestWith: operator, we will get the same emission repeated.
          merge:@[
            [self.mopubSDKInitialized mapReplace:@(SourceEventStarted)],
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
                  // Event source is not from the change in AppEvent properties.
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

    }

    // Ad controller signals:
    // Subscribes to the infinite signals that are responsible for loading ads.
    {

        // Untunneled interstitial
        [self.compoundDisposable addDisposable:[self subscribeToAdSignalForAd:self.untunneledInterstitial
                                                withActionLoadDelayedInterval:5.0
                                                        withLoadInTunnelState:TunnelStateUntunneled
                                                      reloadAdAfterPresenting:AdLoadActionDelayed]];

        // Untunneled rewarded video
        [self.compoundDisposable addDisposable:[self subscribeToAdSignalForAd:self.untunneledRewardVideo
                                                withActionLoadDelayedInterval:1.0
                                                        withLoadInTunnelState:TunnelStateUntunneled
                                                      reloadAdAfterPresenting:AdLoadActionImmediate]];

        // Tunneled rewarded video
        [self.compoundDisposable addDisposable:[self subscribeToAdSignalForAd:self.tunneledRewardVideo
                                                withActionLoadDelayedInterval:1.0
                                                        withLoadInTunnelState:TunnelStateTunneled
                                                      reloadAdAfterPresenting:AdLoadActionImmediate]];
    }

    // Ad presentation signals:
    // Merges ad presentation status from all signals.
    //
    // NOTE: It is assumed here that only one ad is shown at a time, and once an ad is presenting none of the
    //       other ad controllers will change their presentation status.
    {
        // Underlying signal will emit @(TRUE) if an ad is presenting, and @(FALSE) otherwise.
        RACMulticastConnection<NSNumber *> *adPresentationMultiCast = [[[[[[RACSignal
          merge:@[
            self.untunneledInterstitial.presentationStatus,
            self.untunneledRewardVideo.presentationStatus,
            self.tunneledRewardVideo.presentationStatus
          ]]
          filter:^BOOL(NSNumber *presentationStatus) {
              AdPresentation ap = (AdPresentation) [presentationStatus integerValue];

              // Filter out all states that are not related to an ad view controller being presented.
              return (ap != AdPresentationErrorNoAdsLoaded);
          }]
          map:^NSNumber *(NSNumber *presentationStatus) {
              AdPresentation ap = (AdPresentation) [presentationStatus integerValue];

              // Normal ad presentation chain with no errors:
              // AdPresentationWillAppear -> AdPresentationDidAppear -> AdPresentationWillDisappear
              //   -> AdPresentationDidDisappear

              if (ap == AdPresentationWillAppear) {
                  return @(TRUE);
              } else if (ap != AdPresentationDidAppear || ap != AdPresentationWillDisappear) {
                  // In this branch `ap` is either AdPresentationDidDisappear or one of the error states.
                  return @(FALSE);
              }

          }]
          startWith:@(FALSE)]  // No ads are being shown when the app is launched.
                               // This initializes the adIsShowing signal.
          deliverOnMainThread]
          multicast:self.adIsShowing];

        [self.compoundDisposable addDisposable:[adPresentationMultiCast connect]];
    }

    // Updating AdManager "ad is ready" (untunneledInterstitialIsReady, rewardedVideoIsReady) properties.
    {
        [self.compoundDisposable addDisposable:
          [[self.appEvents.signal flattenMap:^RACSignal<NSNumber *> *(AppEvent *appEvent) {

              if (appEvent.tunnelState == TunnelStateUntunneled) {
                  return RACObserve(self.untunneledInterstitial, ready);
              }
              return [RACSignal return:@(FALSE)];
          }]
          subscribeNext:^(NSNumber *readyObj) {
              BOOL ready = [readyObj boolValue];
              if (self.untunneledInterstitialIsReady != ready) {
                  self.untunneledInterstitialIsReady = ready;
              }
          }]];

        [self.compoundDisposable addDisposable:
          [[self.appEvents.signal flattenMap:^RACSignal<NSNumber *> *(AppEvent *appEvent) {

              if (appEvent.tunnelState == TunnelStateUntunneled) {
                  return RACObserve(self.untunneledRewardVideo, ready);
              } else if (appEvent.tunnelState == TunnelStateUntunneled) {
                  return RACObserve(self.tunneledRewardVideo, ready);
              }

              return [RACSignal return:@(FALSE)];
          }]
          subscribeNext:^(NSNumber *readyObj) {
              BOOL ready = [readyObj boolValue];
              if (self.rewardedVideoIsReady != ready) {
                  self.rewardedVideoIsReady = ready;
              }
          }]];
    }

    // Calls connect on the multicast connection object to start the subscription to the underlying signal.
    // This call is made after all subscriptions to the underlying signal are made, since once connected to,
    // the underlying signal turns into a hot signal.
    [self.compoundDisposable addDisposable:[self.appEvents connect]];

}

- (void)setRewardedVideoCustomData:(NSString *)data {
    [self.untunneledRewardVideo setCustomData:data];
    [self.tunneledRewardVideo setCustomData:data];
}

- (RACSignal<NSNumber *> *)presentInterstitialOnViewController:(UIViewController *)viewController {

    return [self presentAdOnViewController:viewController
                          withAdController:^id <AdControllerWrapperProtocol>(TunnelState tunnelState) {

                              if (TunnelStateUntunneled == tunnelState) {
                                  return self.untunneledInterstitial;
                              }
                              return nil;
                          }];
}

- (RACSignal<NSNumber *> *)presentRewardedVideoOnViewController:(UIViewController *)viewController {

    return [self presentAdOnViewController:viewController
                          withAdController:^id <AdControllerWrapperProtocol>(TunnelState tunnelState) {

                              if (TunnelStateUntunneled == tunnelState) {
                                  return self.untunneledRewardVideo;
                              } else if (TunnelStateTunneled == tunnelState) {
                                  return self.tunneledRewardVideo;
                              }
                              return nil;
                          }];
}

#pragma mark - Helper methods

// Emits items of type @(AdPresentation). Emits `AdPresentationErrorInappropriateState` if app is not in the appropriate
// state to present the ad.
// Note: `adControllerBlock` should return `nil` if the TunnelState is not in the appropriate state.
- (RACSignal<NSNumber *> *)presentAdOnViewController:(UIViewController *)viewController
              withAdController:(id <AdControllerWrapperProtocol>(^_Nonnull)(TunnelState tunnelState))adControllerBlock {

    return [[[self.appEvents.signal take:1]
      flattenMap:^RACSignal *(AppEvent *event) {

          // Ads are loaded based on app event condition at the time of load, and unloaded during certain app events
          // like when the user buys a subscription. Still necessary conditions (like network reachability)
          // should be checked again before presenting the ad.
          if (event.networkIsReachable) {

              id <AdControllerWrapperProtocol> adController = nil;
              if (event.tunnelState != TunnelStateNeither) {
                  adController = adControllerBlock(event.tunnelState);
              }

              if (adController) {
                  return [adController presentAdFromViewController:viewController];
              }
          }

          return [RACSignal return:@(AdPresentationErrorInappropriateState)];
      }]
      subscribeOn:RACScheduler.mainThreadScheduler];
}

- (RACDisposable *)subscribeToAdSignalForAd:(id <AdControllerWrapperProtocol>)adController
              withActionLoadDelayedInterval:(NSTimeInterval)delayedAdLoadDelay
                      withLoadInTunnelState:(TunnelState)loadTunnelState
                    reloadAdAfterPresenting:(AdLoadAction)afterPresentationLoadAction {

    PSIAssert(loadTunnelState != TunnelStateNeither);

    // It is assumed that `adController` objects live as long as the AdManager class.
    // Therefore reactive declaration below holds a strong references to the `adController` object.

    // Retry count for ads that failed to load (doesn't apply for expired ads).
    NSInteger const AD_LOAD_RETRY_COUNT = 1;
    NSTimeInterval const MIN_AD_RELOAD_TIMER = 1.0;

    NSString * const TriggerAdPresented = @"adPresented";
    NSString * const TriggerAppEvent = @"appEvent";

    // adPresentedAppEvent is hot infinite signal - emits tuple (TriggerAdPresented, AppEvent*) whenever the ad
    // from `adController` is dismissed and no longer presented.
    RACSignal<RACTwoTuple<NSString*,AppEvent*>*> *adPresentedAppEvent =
      [adController.adPresented flattenMap:^RACSignal<AppEvent *> *(RACUnit *value) {
        // Return the cached value of `appEvents`.
        return [[self.appEvents.signal take:1] map:^RACTwoTuple<NSString*,AppEvent*>*(AppEvent *event) {
            return [RACTwoTuple pack:TriggerAdPresented :event];
        }];
    }];

    // appEventWithSource is the same as `appEvents.signal`, mapped to the tuple (TriggerAppEvent, AppEvent*).
    RACSignal<RACTwoTuple<NSString*,AppEvent*>*> *appEventWithSource =
      [self.appEvents.signal map:^id(AppEvent *event) {
        return [RACTwoTuple pack:TriggerAppEvent :event];
    }];

    RACSignal<AppEventActionTuple *> *adActionSignal = [[[RACSignal
      merge:@[adPresentedAppEvent, appEventWithSource]]
      map:^AppEventActionTuple *(RACTwoTuple<NSString*,AppEvent*> *tuple) {

          NSString *triggerSignal = tuple.first;
          AppEvent *event = tuple.second;

          AppEventActionTuple *sa = [[AppEventActionTuple alloc] init];
          sa.tag = adController.tag;
          sa.actionCondition = event;
          // Default value if no decision has been reached.
          sa.action = AdLoadActionNone;

          if (event.subscriptionIsActive) {
              sa.stopCondition = [RACSignal never];
              sa.action = AdLoadActionUnload;

          } else if (event.networkIsReachable) {

              sa.stopCondition = [self.appEvents.signal filter:^BOOL(AppEvent *current) {
                  BOOL condition = ![sa.actionCondition isEqual:current];
                  if (condition) LOG_DEBUG(@"Ad stopCondition for %@", sa.tag);
                  return condition;
              }];

              // If the current tunnel state is the same as the ads tunnel state, then load ad.
              if (event.tunnelState == loadTunnelState && !adController.ready) {

                  if ([TriggerAdPresented isEqualToString:triggerSignal]) {
                      // The user has just finished viewing the ad.
                      sa.action = afterPresentationLoadAction;

                  } else if (event.source == SourceEventStarted) {
                      // The app has just been launched, don't delay the ad load.
                      sa.action = AdLoadActionImmediate;

                  } else {
                      // For all the other event sources, load the ad after a delay.
                      sa.action = AdLoadActionDelayed;
                  }
              }
          }

          return sa;
      }]
      filter:^BOOL(AppEventActionTuple *v) {
          // Removes "no actions" from the stream again, since no action should be taken.
          return (v.action != AdLoadActionNone);
      }];
    
    
      return [[[adActionSignal map:^RACSignal<NSNumber *> *(AppEventActionTuple *v) {

          // Transforms the load signal by adding retry logic.
          // The returned signal does not throw any errors.
          return [[[[[RACSignal return:v]
            flattenMap:^RACSignal<NSString *> *(AppEventActionTuple *sourceAction) {

                switch (sourceAction.action) {

                    case AdLoadActionImmediate:
                        return [adController loadAd];

                    case AdLoadActionDelayed:
                        return [[RACSignal timer:delayedAdLoadDelay]
                          flattenMap:^RACSignal *(id x) {
                              return [adController loadAd];
                          }];

                    case AdLoadActionUnload:
                        return [adController unloadAd];

                    default:
                        PSIAssert(FALSE);
                        return [RACSignal empty];
                }
            }]
            takeUntil:v.stopCondition]
            retryWhen:^RACSignal *(RACSignal<NSError *> *errors) {
                // Groups errors into two types:
                // - For errors that are due expired ads, always reload and get a new ad.
                // - For other types of errors, try to reload only one more time after a delay.
                return [[errors groupBy:^NSString *(NSError *error) {
                      if ([AdControllerWrapperErrorDomain isEqualToString:error.domain]) {
                          if (AdControllerWrapperErrorAdExpired == error.code) {
                              // Always get a new ad for expired ads.
                              return @"retryForever";
                          }
                      }
                      return @"otherError";
                  }]
                  flattenMap:^RACSignal *(RACGroupedSignal *groupedErrors) {
                      NSString *groupKey = (NSString *) groupedErrors.key;
                      
                      if ([@"retryForever" isEqualToString:groupKey]) {
                          return [groupedErrors flattenMap:^RACSignal *(id x) {
                              return [RACSignal timer:MIN_AD_RELOAD_TIMER];
                          }];
                      } else {
                          return [[groupedErrors zipWith:[RACSignal rangeStartFrom:0 count:(AD_LOAD_RETRY_COUNT+1)]]
                              flattenMap:^RACSignal *(RACTwoTuple *value) {

                                  NSError *error = value.first;
                                  NSInteger retryCount = [(NSNumber *)value.second integerValue];

                                  if (retryCount == AD_LOAD_RETRY_COUNT) {
                                      // Reached max retry.
                                      return [RACSignal error:error];
                                  } else {
                                      // Try to load ad again after `MIN_AD_RELOAD_TIMER` second after a failure.
                                      return [RACSignal timer:MIN_AD_RELOAD_TIMER];
                                  }
                              }];
                      }
                  }];
            }]
            catch:^RACSignal *(NSError *error) {
                // Catch all errors.
                return [RACSignal return:nil];
            }];

      }]
      switchToLatest]
      subscribeNext:^(NSString *_Nullable adTag) {
          if (adTag != nil) {
              LOG_DEBUG(@"Finished loading ad (%@)", adTag);
              [PsiFeedbackLogger infoWithType:AdManagerLogType json:@{@"event": @"adDidLoad", @"tag": adTag}];
          }
      }
      error:^(NSError *error) {
          // Signal should never terminate.
          PSIAssert(error);
      }
      completed:^{
          // Signal should never terminate.
           PSIAssert(FALSE);
      }];
}

@end
