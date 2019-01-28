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
#import "MoPubInterstitialAdControllerWrapper.h"
#import "MoPubRewardedAdControllerWrapper.h"
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
#import "MoPubConsent.h"
#import "AdMobInterstitialAdControllerWrapper.h"
#import "AdMobRewardedAdControllerWrapper.h"
#import <PersonalizedAdConsent/PersonalizedAdConsent.h>
#import "AdMobConsent.h"
#import "AppEvent.h"


NSErrorDomain const AdControllerWrapperErrorDomain = @"AdControllerWrapperErrorDomain";

PsiFeedbackLogType const AdManagerLogType = @"AdManager";

#pragma mark - Ad IDs

NSString * const GoogleAdMobAppID = @"ca-app-pub-1072041961750291~2085686375";
NSString * const AdMobPublisherID = @"pub-1072041961750291";

NSString * const UntunneledAdMobInterstitialAdUnitID = @"ca-app-pub-1072041961750291/8751062454";
NSString * const UntunneledAdMobRewardedVideoAdUnitID = @"ca-app-pub-1072041961750291/8356247142";
NSString * const MoPubTunneledRewardVideoAdUnitID    = @"b9440504384740a2a3913a3d1b6db80e";

// AdControllerTag values must be unique.
AdControllerTag const AdControllerTagUntunneledInterstitial = @"UntunneledInterstitial";
AdControllerTag const AdControllerTagUntunneledRewardedVideo = @"UntunneledRewardedVideo";
AdControllerTag const AdControllerTagTunneledRewardedVideo = @"TunneledRewardedVideo";

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
/** Ad controller associated with this AppEventActionTuple. */
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
@property (nonatomic, readwrite, nonnull) RACReplaySubject<NSNumber *> *untunneledInterstitialCanPresent;
@property (nonatomic, readwrite, nonnull) RACReplaySubject<NSNumber *> *rewardedVideoCanPresent;

// Private properties
@property (nonatomic, readwrite, nonnull) AdMobInterstitialAdControllerWrapper *untunneledInterstitial;
@property (nonatomic, readwrite, nonnull) AdMobRewardedAdControllerWrapper *untunneledRewardVideo;
@property (nonatomic, readwrite, nonnull) MoPubRewardedAdControllerWrapper *tunneledRewardVideo;

// appEvents is hot infinite multicasted signal with underlying replay subject.
@property (nonatomic, nullable) RACMulticastConnection<AppEvent *> *appEvents;

@property (nonatomic, nonnull) RACCompoundDisposable *compoundDisposable;

// adSDKInitMultiCast is a terminating multicasted signal that emits RACUnit only once and
// completes immediately when all the Ad SDKs have been initialized (and user consent is collected if necessary).
@property (nonatomic, nullable) RACMulticastConnection<RACUnit *> *adSDKInitMultiCast;

@end

@implementation AdManager {
    Reachability *reachability;
}

- (instancetype)init {
    self = [super init];
    if (self) {

        _adIsShowing = [RACReplaySubject replaySubjectWithCapacity:1];

        _untunneledInterstitialCanPresent = [RACReplaySubject replaySubjectWithCapacity:1];
        [_untunneledInterstitialCanPresent sendNext:@(FALSE)];

        _rewardedVideoCanPresent = [RACReplaySubject replaySubjectWithCapacity:1];
        [_rewardedVideoCanPresent sendNext:@(FALSE)];

        _compoundDisposable = [RACCompoundDisposable compoundDisposable];

        _untunneledInterstitial = [[AdMobInterstitialAdControllerWrapper alloc]
          initWithAdUnitID:UntunneledAdMobInterstitialAdUnitID withTag:AdControllerTagUntunneledInterstitial];

        _untunneledRewardVideo = [[AdMobRewardedAdControllerWrapper alloc]
          initWithAdUnitID:UntunneledAdMobRewardedVideoAdUnitID withTag:AdControllerTagUntunneledRewardedVideo];

        _tunneledRewardVideo = [[MoPubRewardedAdControllerWrapper alloc]
          initWithAdUnitID:MoPubTunneledRewardVideoAdUnitID withTag:AdControllerTagTunneledRewardedVideo];

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

    // adSDKInitConsent is cold terminating signal - Emits RACUnit and completes if all Ad SDKs are initialized and
    // consent is collected. Otherwise terminates with an error.
    RACSignal<RACUnit *> *adSDKInitConsent = [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {
        dispatch_async_main(^{
          [AdMobConsent collectConsentForPublisherID:AdMobPublisherID
                           withCompletionHandler:^(NSError *error, PACConsentStatus consentStatus) {

                if (error) {
                    // Stop ad initialization and don't load any ads.
                    [subscriber sendError:error];
                    return;
                }

                // Implementation follows these guides:
                //  - https://developers.mopub.com/docs/ios/initialization/
                //  - https://developers.mopub.com/docs/mediation/networks/google/

                // Forwards user's ad preference to AdMob.
                MPGoogleGlobalMediationSettings *googleMediationSettings =
                  [[MPGoogleGlobalMediationSettings alloc] init];

                googleMediationSettings.npa = [AdMobConsent NPAStringforConsentStatus:consentStatus];

                // MPMoPubConfiguration should be instantiated with any valid ad unit ID from the app.
                MPMoPubConfiguration *sdkConfig = [[MPMoPubConfiguration alloc]
                  initWithAdUnitIdForAppInitialization:MoPubTunneledRewardVideoAdUnitID];

                sdkConfig.globalMediationSettings = @[googleMediationSettings];

                // Initializes the MoPub SDK and then checks GDPR applicability and show the consent modal screen
                // if necessary.
                [[MoPub sharedInstance] initializeSdkWithConfiguration:sdkConfig completion:^{
                    LOG_DEBUG(@"MoPub SDK initialized");

                    // Concurrency Note: MoPub invokes the completion handler on a concurrent background queue.
                    dispatch_async_main(^{
                        [MoPubConsent collectConsentWithCompletionHandler:^(NSError *error) {
                            if (error) {
                                // Stop ad initialization and don't load any ads.
                                [subscriber sendError:error];
                                return;
                            }

                            [GADMobileAds configureWithApplicationID:GoogleAdMobAppID];

                            // MoPub consent dialog was presented successfully and dismissed
                            // or consent is already given or is not needed.
                            // We can start loading ads.
                            [PsiFeedbackLogger infoWithType:AdManagerLogType message:@"adSDKInitSucceeded"];
                            [subscriber sendNext:RACUnit.defaultUnit];
                            [subscriber sendCompleted];
                        }];
                    });

                }];
            }];
        });

        return nil;
    }];

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

    }

    // Ad SDK initialization
    {
        self.adSDKInitMultiCast = [[[[[[[self.appEvents.signal filter:^BOOL(AppEvent *event) {
              // Initialize Ads SDK if network is reachable, and device is either tunneled or untunneled, and the
              // user is not a subscriber.
              return (event.networkIsReachable &&
                event.tunnelState != TunnelStateNeither &&
                !event.subscriptionIsActive);
          }]
          take:1]
          flattenMap:^RACSignal<RACUnit *> *(AppEvent *value) {
            // Retry 3 time by resubscribing to adSDKInitConsent before giving up for the current AppEvent emission.
            return [adSDKInitConsent retry:3];
          }]
          retry]   // If still failed after retrying 3 times, retry again by resubscribing to the `appEvents.signal`.
          take:1]
          deliverOnMainThread]
          multicast:[RACReplaySubject replaySubjectWithCapacity:1]];

        [self.compoundDisposable addDisposable:[self.adSDKInitMultiCast connect]];
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

        // Underlying signal emits @(TRUE) if an ad is presenting, and @(FALSE) otherwise.
        RACMulticastConnection<NSNumber *> *adPresentationMultiCast = [[[[[RACSignal
          merge:@[
            self.untunneledInterstitial.presentationStatus,
            self.untunneledRewardVideo.presentationStatus,
            self.tunneledRewardVideo.presentationStatus
          ]]
          map:^NSNumber *(NSNumber *presentationStatus) {
              AdPresentation ap = (AdPresentation) [presentationStatus integerValue];

              // Returns @(TRUE) if ad is being presented, and `ap` is not one of the error states.
              return @(adBeingPresented(ap));
          }]
          startWith:@(FALSE)]  // No ads are being shown when the app is launched.
                               // This initializes the adIsShowing signal.
          deliverOnMainThread]
          multicast:self.adIsShowing];

        [self.compoundDisposable addDisposable:[adPresentationMultiCast connect]];
    }

    // Updating AdManager "ad is ready" (untunneledInterstitialCanPresent, rewardedVideoCanPresent) properties.
    {
        [self.compoundDisposable addDisposable:
          [[[self.appEvents.signal map:^RACSignal<NSNumber *> *(AppEvent *appEvent) {

              if (appEvent.tunnelState == TunnelStateUntunneled && appEvent.networkIsReachable) {

                  return RACObserve(self.untunneledInterstitial, ready);
              }
              return [RACSignal emitOnly:@(FALSE)];
          }]
          switchToLatest]
          subscribe:self.untunneledInterstitialCanPresent]];

        [self.compoundDisposable addDisposable:
          [[[self.appEvents.signal map:^RACSignal<NSNumber *> *(AppEvent *appEvent) {

              if (appEvent.networkIsReachable) {
                  if (appEvent.tunnelState == TunnelStateUntunneled) {
                      return RACObserve(self.untunneledRewardVideo, ready);
                  } else if (appEvent.tunnelState == TunnelStateTunneled) {
                      return RACObserve(self.tunneledRewardVideo, ready);
                  }
              }

              return [RACSignal emitOnly:@(FALSE)];
          }]
          switchToLatest]
          subscribe:self.rewardedVideoCanPresent]];
    }

    // Calls connect on the multicast connection object to start the subscription to the underlying signal.
    // This call is made after all subscriptions to the underlying signal are made, since once connected to,
    // the underlying signal turns into a hot signal.
    [self.compoundDisposable addDisposable:[self.appEvents connect]];

}

- (void)resetUserConsent {
    [AdMobConsent resetConsent];
}

- (RACSignal<NSNumber *> *)presentInterstitialOnViewController:(UIViewController *)viewController {

    return [self presentAdHelper:^RACSignal<NSNumber *> *(TunnelState tunnelState) {
        if (TunnelStateUntunneled == tunnelState) {
            return [self.untunneledInterstitial presentAdFromViewController:viewController];
        }
        return [RACSignal empty];
    }];
}

- (RACSignal<NSNumber *> *)presentRewardedVideoOnViewController:(UIViewController *)viewController
                                                 withCustomData:(NSString *_Nullable)customData{

    return [self presentAdHelper:^RACSignal<NSNumber *> *(TunnelState tunnelState) {
        switch (tunnelState) {
            case TunnelStateTunneled:
                return [self.tunneledRewardVideo presentAdFromViewController:viewController
                                                              withCustomData:customData];
            case TunnelStateUntunneled:
                return [self.untunneledRewardVideo presentAdFromViewController:viewController
                                                                withCustomData:customData];
            case TunnelStateNeither:
                return [RACSignal empty];

            default:
                abort();
        }
    }];
}

#pragma mark - Helper methods

// Emits items of type @(AdPresentation). Emits `AdPresentationErrorInappropriateState` if app is not in the appropriate
// state to present the ad.
// Note: `adControllerBlock` should return `nil` if the TunnelState is not in the appropriate state.
- (RACSignal<NSNumber *> *)presentAdHelper:(RACSignal<NSNumber *> *(^_Nonnull)(TunnelState tunnelState))adControllerBlock {

    return [[[self.appEvents.signal take:1]
      flattenMap:^RACSignal<NSNumber *> *(AppEvent *event) {

          // Ads are loaded based on app event condition at the time of load, and unloaded during certain app events
          // like when the user buys a subscription. Still necessary conditions (like network reachability)
          // should be checked again before presenting the ad.

          if (event.networkIsReachable) {

              if (event.tunnelState != TunnelStateNeither) {
                  RACSignal<NSNumber *> *_Nullable presentationSignal = adControllerBlock(event.tunnelState);

                  if (presentationSignal) {
                      return presentationSignal;
                  }
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

    // List of "trigger"s.
    NSString * const TriggerPresentedAdDismissed = @"presentedAdDismissed";
    NSString * const TriggerAppEvent = @"appEvent";

    // presentedAdDismissedWithAppEvent is hot infinite signal - emits tuple (TriggerPresentedAdDismissed, AppEvent*)
    // whenever the ad from `adController` is dismissed and no longer presented.
    RACSignal<RACTwoTuple<NSString*,AppEvent*>*> *presentedAdDismissedWithAppEvent =
      [adController.presentedAdDismissed flattenMap:^RACSignal<AppEvent *> *(RACUnit *value) {
        // Return the cached value of `appEvents`.
        return [[self.appEvents.signal take:1] map:^RACTwoTuple<NSString*,AppEvent*>*(AppEvent *event) {
            return [RACTwoTuple pack:TriggerPresentedAdDismissed :event];
        }];
    }];

    // appEventWithSource is the same as `appEvents.signal`, mapped to the tuple (TriggerAppEvent, AppEvent*).
    RACSignal<RACTwoTuple<NSString*,AppEvent*>*> *appEventWithSource =
      [self.appEvents.signal map:^id(AppEvent *event) {
        return [RACTwoTuple pack:TriggerAppEvent :event];
    }];

    RACSignal<RACTwoTuple<AdControllerTag, AppEventActionTuple *> *> *adLoadUnloadSignal = [[[[[RACSignal
      merge:@[presentedAdDismissedWithAppEvent, appEventWithSource]]
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

              AppEventActionTuple *__weak weakSa = sa;

              sa.stopCondition = [self.appEvents.signal filter:^BOOL(AppEvent *current) {
                  // Since `sa` already holds a strong reference to this block, the block
                  // should only hold a weak reference to `sa`.
                  AppEventActionTuple *__strong strongSa = weakSa;
                  BOOL pass = FALSE;
                  if (strongSa) {
                      pass = ![weakSa.actionCondition isEqual:current];
                      if (pass) LOG_DEBUG(@"Ad stopCondition for %@", weakSa.tag);
                  }
                  return pass;
              }];

              // If the current tunnel state is the same as the ads required tunnel state, then load ad.
              if (event.tunnelState == loadTunnelState && !adController.ready) {

                  if ([TriggerPresentedAdDismissed isEqualToString:triggerSignal]) {
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
      }]
      map:^RACSignal<RACTwoTuple<AdControllerTag, AppEventActionTuple *> *> *(AppEventActionTuple *v) {

          // Transforms the load signal by adding retry logic.
          // The returned signal does not throw any errors.
          return [[[[[RACSignal return:v]
            flattenMap:^RACSignal<RACTwoTuple<AdControllerTag, AppEventActionTuple *> *> *
              (AppEventActionTuple *sourceAction) {

                RACSignal<AdControllerTag> *returnedSignal;

                switch (sourceAction.action) {

                    case AdLoadActionImmediate: {
                        returnedSignal = [adController loadAd];
                        break;
                    }
                    case AdLoadActionDelayed: {
                        returnedSignal = [[RACSignal timer:delayedAdLoadDelay]
                          flattenMap:^RACSignal *(id x) {
                              return [adController loadAd];
                          }];
                        break;
                    }
                    case AdLoadActionUnload: {
                        returnedSignal = [adController unloadAd];
                        break;
                    }
                    default: {
                        PSIAssert(FALSE);
                        return [RACSignal empty];
                    }
                }

                return [returnedSignal map:^id(AdControllerTag tag) {
                    // Pack the source action with emission of `returnedSignal`.
                    return [RACTwoTuple pack:tag :sourceAction];
                }];
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
                              [PsiFeedbackLogger warnWithType:AdManagerLogType
                                                         json:@{@"event": @"adDidExpire",
                                                           @"tag": v.tag,
                                                           @"NSError": [PsiFeedbackLogger unpackError:error]}];

                              return @"retryForever";

                          } else if (AdControllerWrapperErrorAdFailedToLoad == error.code) {
                              // Get a new ad `AD_LOAD_RETRY_COUNT` times.
                              [PsiFeedbackLogger errorWithType:AdManagerLogType
                                                          json:@{@"event": @"adDidFailToLoad",
                                                            @"tag": v.tag,
                                                            @"NSError": [PsiFeedbackLogger unpackError:error]}];
                              return @"retryOther";
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
      switchToLatest];

    return [[self.adSDKInitMultiCast.signal
      then:^RACSignal<RACTwoTuple<AdControllerTag, AppEventActionTuple *> *> * {
          return adLoadUnloadSignal;
      }]
      subscribeNext:^(RACTwoTuple<AdControllerTag, AppEventActionTuple *> *_Nullable tuple) {

          if (tuple != nil) {

              AppEventActionTuple *appEventCommand = tuple.second;

              if (appEventCommand.action != AdLoadActionNone) {

                  if (appEventCommand.action == AdLoadActionUnload) {
                      // Unload action.
                      [PsiFeedbackLogger infoWithType:AdManagerLogType
                                                 json:@{@"event": @"adDidUnload", @"tag": appEventCommand.tag}];
                  } else {
                      // Load actions.
                      [PsiFeedbackLogger infoWithType:AdManagerLogType
                                                 json:@{@"event": @"adDidLoad", @"tag": appEventCommand.tag}];
                  }
              }
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
