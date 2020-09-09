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
#import "AppDelegate.h"
#import "Logging.h"
#import "RACCompoundDisposable.h"
#import "RACSignal.h"
#import "RACSignal+Operations.h"
#import "RACReplaySubject.h"
#import "DispatchUtils.h"
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
#import "AdMobInterstitialAdControllerWrapper.h"
#import "AdMobRewardedAdControllerWrapper.h"
#import "AppEvent.h"
#import "AppObservables.h"
#import "Psiphon-Swift.h"

NSErrorDomain const AdControllerWrapperErrorDomain = @"AdControllerWrapperErrorDomain";

PsiFeedbackLogType const AdManagerLogType = @"AdManager";

#pragma mark - Ad IDs

NSString * const GoogleAdMobAppID = @"ca-app-pub-1072041961750291~2085686375";
NSString * const AdMobPublisherID = @"pub-1072041961750291";

#if DEBUG
// Demo ad unit Ids: https://developers.google.com/admob/ios/test-ads
NSString * const UntunneledAdMobInterstitialAdUnitID = @"ca-app-pub-3940256099942544/4411468910";
NSString * const UntunneledAdMobRewardedVideoAdUnitID = @"ca-app-pub-3940256099942544/1712485313";
#else
NSString * const UntunneledAdMobInterstitialAdUnitID = @"ca-app-pub-1072041961750291/8751062454";
NSString * const UntunneledAdMobRewardedVideoAdUnitID = @"ca-app-pub-1072041961750291/8356247142";
#endif

// AdControllerTag values must be unique.
AdControllerTag const AdControllerTagAdMobUntunneledInterstitial = @"AdMobUntunneledInterstitial";
AdControllerTag const AdControllerTagAdMobUntunneledRewardedVideo = @"AdMobUntunneledRewardedVideo";

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
    
    return [NSString stringWithFormat:@"<AppEventActionTuple tag=%@ action=%@ actionCondition=%@ stopCondition=%p>",
                                      self.tag, actionText, [self.actionCondition debugDescription], self.stopCondition];
}

@end


#pragma mark - Ad Manager class

@interface AdManager ()

@property (nonatomic, readwrite, nonnull) RACSubject<RACUnit *> *adSDKStarted;

@property (nonatomic, readwrite, nonnull) RACBehaviorSubject<NSNumber *> *adIsShowing;
@property (nonatomic, readwrite, nonnull) RACBehaviorSubject<NSNumber *> *untunneledInterstitialLoadStatus;
@property (nonatomic, readwrite, nonnull) RACBehaviorSubject<NSNumber *> *rewardedVideoLoadStatus;
@property (nonatomic, readwrite, nonnull) RACSubject<RACUnit *> *forceRewardedVideoLoad;

// Private properties
@property (nonatomic, readwrite, nonnull) AdMobInterstitialAdControllerWrapper *untunneledInterstitial;
@property (nonatomic, readwrite, nonnull) AdMobRewardedAdControllerWrapper *untunneledRewardVideo;

@property (nonatomic, nonnull) RACCompoundDisposable *compoundDisposable;

// adSDKInitMultiCast is a terminating multicasted signal that emits RACUnit only once and
// completes immediately when all the Ad SDKs have been initialized (and user consent is collected if necessary).
@property (nonatomic, nullable) RACMulticastConnection<RACUnit *> *adSDKInitMultiCast;

@end

@implementation AdManager

- (instancetype)init {
    self = [super init];
    if (self) {
        
        _adSDKStarted = [RACSubject subject];

        _adIsShowing = [RACBehaviorSubject behaviorSubjectWithDefaultValue:@(FALSE)];

        _untunneledInterstitialLoadStatus = [RACBehaviorSubject behaviorSubjectWithDefaultValue:@(AdLoadStatusNone)];

        _rewardedVideoLoadStatus = [RACBehaviorSubject behaviorSubjectWithDefaultValue:@(AdLoadStatusNone)];

        _forceRewardedVideoLoad = [RACSubject subject];

        _compoundDisposable = [RACCompoundDisposable compoundDisposable];

        _untunneledInterstitial = [[AdMobInterstitialAdControllerWrapper alloc]
          initWithAdUnitID:UntunneledAdMobInterstitialAdUnitID
                   withTag:AdControllerTagAdMobUntunneledInterstitial];

        _untunneledRewardVideo = [[AdMobRewardedAdControllerWrapper alloc]
          initWithAdUnitID:UntunneledAdMobRewardedVideoAdUnitID
                   withTag:AdControllerTagAdMobUntunneledRewardedVideo];

    }
    return self;
}

- (void)dealloc {
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

- (void)initializeAdManager {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [self _initializeAdManager];
    });
}

- (void)initializeRewardedVideos {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [self _initializeRewardedVideos];
    });
}

// This should be called only once at application launch time
- (void)_initializeAdManager {

    AdManager *__weak weakSelf = self;

    // adSDKInitConsent is cold terminating signal - Emits RACUnit and completes if all Ad SDKs are initialized and
    // consent is collected. Otherwise terminates with an error.
    RACSignal<RACUnit *> *adSDKInitConsent = [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {
        dispatch_async_main(^{
            
            // AdMob Warning: Ads may be preloaded by the Mobile Ads SDK or mediation partner SDKs
            // upon calling startWithCompletionHandler:. If you need to obtain consent from
            // users in the European Economic Area (EEA), set any request-specific flags (such as
            // tagForChildDirectedTreatment or tag_for_under_age_of_consent), or otherwise
            // take action before loading ads, ensure you do so before
            // initializing the Mobile Ads SDK.
            
            [AdConsent.sharedInstance consentInfoUpdateWithCompletionHandler:^(NSError * _Nullable error) {
                if (error != nil) {
                    [subscriber sendError:error];
                    return;
                }
                
                [AdConsent.sharedInstance presentConsentFormIfNeededFromViewController:^UIViewController * _Nonnull{
                    return [AppDelegate getTopPresentedViewController];
                } completionHandler:^(NSError * _Nullable error, UMPConsentStatus status) {
                    
                    if (error != nil) {
                        [subscriber sendError:error];
                        return;
                    }
                    
                    // Starts Google AdMob SDK.
                    [GADMobileAds.sharedInstance startWithCompletionHandler:
                     ^(GADInitializationStatus * _Nonnull status) {

                        [PsiFeedbackLogger
                         infoWithType:AdManagerLogType
                         message:[NSString stringWithFormat:@"Initialized AdMob SDK '%@'",
                                  status.adapterStatusesByClassName]];
                        
                        [subscriber sendNext:RACUnit.defaultUnit];
                        [subscriber sendCompleted];
                    }];
                }];
            }];
        });

        return nil;
    }];

    // Ad SDK initialization
    {
        self.adSDKInitMultiCast = [[[[[[[[[AppObservables shared].appEvents.signal filter:^BOOL(AppEvent *event) {
              // Initialize Ads SDK if network is reachable, and device is either tunneled or untunneled, and the
              // user is not a subscriber.
              return (event.networkIsReachable &&
                event.tunnelState != TunnelStateNeither &&
                !event.subscriptionIsActive);
          }]
          take:1]
          flattenMap:^RACSignal<RACUnit *> *(AppEvent *value) {
              return adSDKInitConsent;
          }] doError:^(NSError * _Nonnull error) {
              // Logs error emitted by `adSDKInitConsent` signal.
              [PsiFeedbackLogger errorWithType:AdManagerLogType message:@"Ad SDK init failed"
                                        object:error];
          }]
          retry:3]
          take:1]
          deliverOnMainThread]
          multicast:[RACReplaySubject replaySubjectWithCapacity:1]];

        [self.compoundDisposable addDisposable:[self.adSDKInitMultiCast connect]];
        
        [self.compoundDisposable addDisposable:
         [self.adSDKInitMultiCast.signal subscribe:self.adSDKStarted]];
    }

    // Ad controller signals:
    // Subscribes to the infinite signals that are responsible for loading ads.
    {

        // Untunneled interstitial
        [self.compoundDisposable addDisposable:[self subscribeToAdSignalForAd:self.untunneledInterstitial
                                                withActionLoadDelayedInterval:5.0
                                                        withLoadInTunnelState:TunnelStateUntunneled
                                                      reloadAdAfterPresenting:AdLoadActionDelayed
                                        andWaitForPsiCashRewardedActivityData:FALSE]];
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
            self.untunneledRewardVideo.presentationStatus
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
          [[[AppObservables.shared.appEvents.signal map:^RACSignal<NSNumber *> *(AppEvent *appEvent) {

              if (appEvent.tunnelState == TunnelStateUntunneled && appEvent.networkIsReachable) {

                  return weakSelf.untunneledInterstitial.adLoadStatus;
              }
              return [RACSignal return:@(AdLoadStatusNone)];
          }]
          switchToLatest]
          subscribe:self.untunneledInterstitialLoadStatus]];

        [self.compoundDisposable addDisposable:
          [[[AppObservables.shared.appEvents.signal map:^RACSignal<NSNumber *> *(AppEvent *appEvent) {

              if (appEvent.networkIsReachable) {

                  if (appEvent.tunnelState == TunnelStateUntunneled) {
                      return weakSelf.untunneledRewardVideo.adLoadStatus;
                  } else if (appEvent.tunnelState == TunnelStateTunneled) {
                      return [RACSignal return:@(AdLoadStatusError)];
                  }
              }

              return [RACSignal return:@(AdLoadStatusNone)];
          }]
          switchToLatest]
          subscribe:self.rewardedVideoLoadStatus]];
    }
}

// This should be called only once at application launch time
- (void)_initializeRewardedVideos {

    // Untunneled rewarded video
    [self.compoundDisposable addDisposable:[self subscribeToAdSignalForAd:self.untunneledRewardVideo
                                            withActionLoadDelayedInterval:1.0
                                                    withLoadInTunnelState:TunnelStateUntunneled
                                                  reloadAdAfterPresenting:AdLoadActionImmediate
                                    andWaitForPsiCashRewardedActivityData:TRUE]];

}

- (void)resetUserConsent {
    [AdConsent.sharedInstance resetConsent];
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
                return [RACSignal empty];
            case TunnelStateUntunneled:
                return [self.untunneledRewardVideo presentAdFromViewController:viewController];
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

    return [[[AppObservables.shared.appEvents.signal take:1]
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
                      withLoadInTunnelState:(TunnelState)loadInTunnelState
                    reloadAdAfterPresenting:(AdLoadAction)afterPresentationLoadAction
      andWaitForPsiCashRewardedActivityData:(BOOL)waitForPsiCashRewardedActivityData {

    PSIAssert(loadInTunnelState != TunnelStateNeither);

    // It is assumed that `adController` objects live as long as the AdManager class.
    // Therefore reactive declaration below holds a strong references to the `adController` object.

    // Retry `groupBy` types.
    NSString * const RetryTypeForever = @"RetryTypeForever";
    NSString * const RetryTypeDoNotRetry = @"RetryTypeDoNotRetry";
    NSString * const RetryTypeOther = @"RetryTypeOther";

    // Delay time between reloads.
    NSTimeInterval const MIN_AD_RELOAD_TIMER = 1.0;

    // "Trigger" signals.
    NSString * const TriggerPresentedAdDismissed = @"TriggerPresentedAdDismissed";
    NSString * const TriggerAppEvent = @"TriggerAppEvent";
    NSString * const TriggerPsiCashRewardedActivityDataUpdated = @"TriggerPsiCashRewardedActivityDataUpdated";
    NSString * const TriggerForceRewardedVideoLoad = @"TriggerForceRewardedVideoLoad";

    RACSignal<NSString *> *triggers;

    // Max number of ad load retries.
    NSInteger adLoadMaxRetries = 0;

    if (AdFormatRewardedVideo == adController.adFormat) {
        adLoadMaxRetries = 0;

        // Setup triggers for rewarded video ads.
        triggers = [self.forceRewardedVideoLoad mapReplace:TriggerForceRewardedVideoLoad];

    } else if (AdFormatInterstitial == adController.adFormat) {
        adLoadMaxRetries = 1;

        // Setup triggers for interstitial ads.
        triggers = [RACSignal merge:@[
          [AppObservables.shared.appEvents.signal mapReplace:TriggerAppEvent],
          [adController.presentedAdDismissed mapReplace:TriggerPresentedAdDismissed],
        ]];

    } else {
        PSIAssert(FALSE);
    }

    RACSignal<RACTwoTuple<AdControllerTag, AppEventActionTuple *> *> *adLoadUnloadSignal =
      [[[[[triggers withLatestFrom:AppObservables.shared.appEvents.signal]
      map:^AppEventActionTuple *(RACTwoTuple<NSString *, AppEvent *> *tuple) {

          // In disambiguating the source of the event emission:
          //  - If `triggerSignal` string below is "TriggerAppEvent", then
          //    the source is defined in `event.source` below.
          //  - Otherwise, the trigger signal is the source as defined in one of the Trigger_ constants above.

          NSString *triggerSignalName = tuple.first;
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

              sa.stopCondition = [AppObservables.shared.appEvents.signal filter:^BOOL(AppEvent *current) {
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
              if (event.tunnelState == loadInTunnelState) {

                  // Decide action for interstitial ad.
                  if (adController.adFormat == AdFormatInterstitial) {

                      if (event.source == SourceEventStarted) {
                          // The app has just been launched, don't delay the ad load.
                          sa.action = AdLoadActionImmediate;

                      } else if ([TriggerForceRewardedVideoLoad isEqualToString:triggerSignalName]) {
                          // This is a forced load.
                          sa.action = AdLoadActionImmediate;

                      } else {
                          // For all the other event sources, load the ad after a delay.
                          sa.action = AdLoadActionDelayed;
                      }

                      // Decide action for rewarded video ad.
                  } else if (adController.adFormat == AdFormatRewardedVideo) {

                      if ([TriggerForceRewardedVideoLoad isEqualToString:triggerSignalName]) {
                          // This is a forced load.
                          sa.action = AdLoadActionImmediate;

                      }

                  } else {
                      PSIAssert(FALSE);
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

                RACSignal<RACTwoTuple<AdControllerTag, NSError *> *> *loadOrUnload;

                switch (sourceAction.action) {

                    case AdLoadActionImmediate: {
                        loadOrUnload = [adController loadAd];
                        break;
                    }
                    case AdLoadActionDelayed: {
                        loadOrUnload = [[RACSignal timer:delayedAdLoadDelay]
                          flattenMap:^RACSignal *(id x) {
                              return [adController loadAd];
                          }];
                        break;
                    }
                    case AdLoadActionUnload: {
                        loadOrUnload = [adController unloadAd];
                        break;
                    }
                    default: {
                        PSIAssert(FALSE);
                        return [RACSignal empty];
                    }
                }

                return [loadOrUnload flattenMap:^RACSignal *(RACTwoTuple<AdControllerTag, NSError *> *maybeTuple) {
                           NSError *_Nullable error = maybeTuple.second;

                           // Raise the error if it has been emitted.
                           if (error) {
                               return [RACSignal error:error];
                           } else {
                               // Pack the source action with the ad controller's tag.
                               return [RACSignal return:[RACTwoTuple pack:maybeTuple.first :sourceAction]];
                           }
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

                              return RetryTypeForever;

                          } else if (AdControllerWrapperErrorAdFailedToLoad == error.code) {
                              // Get a new ad `AD_LOAD_RETRY_COUNT` times.
                              [PsiFeedbackLogger errorWithType:AdManagerLogType
                                                          json:@{@"event": @"adDidFailToLoad",
                                                            @"tag": v.tag,
                                                            @"NSError": [PsiFeedbackLogger unpackError:error]}];
                              return RetryTypeOther;

                          } else if (AdControllerWrapperErrorCustomDataNotSet == error.code) {
                              [PsiFeedbackLogger errorWithType:AdManagerLogType
                                                          json:@{@"event": @"customDataNotSet",
                                                            @"tag": v.tag,
                                                            @"NSError": [PsiFeedbackLogger unpackError:error]}];
                              return RetryTypeDoNotRetry;
                          }
                      }
                      return RetryTypeOther;
                  }]
                  flattenMap:^RACSignal *(RACGroupedSignal *groupedErrors) {
                      NSString *groupKey = (NSString *) groupedErrors.key;

                      if ([RetryTypeDoNotRetry isEqualToString:groupKey]) {
                        return [RACSignal empty];

                      } else if ([RetryTypeForever isEqualToString:groupKey]) {
                          return [groupedErrors flattenMap:^RACSignal *(id x) {
                              return [RACSignal timer:MIN_AD_RELOAD_TIMER];
                          }];

                      } else {
                          return [[groupedErrors zipWith:[RACSignal rangeStartFrom:0 count:(adLoadMaxRetries+1)]]
                            flattenMap:^RACSignal *(RACTwoTuple *value) {

                                NSError *error = value.first;
                                NSInteger retryCount = [(NSNumber *)value.second integerValue];

                                if (retryCount == adLoadMaxRetries) {
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
                [PsiFeedbackLogger errorWithType:AdManagerLogType
                                            json:@{@"event": @"adLoadErrorPostRetryCaught",
                                              @"tag": v.tag,
                                              @"NSError": [PsiFeedbackLogger unpackError:error]}];
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
