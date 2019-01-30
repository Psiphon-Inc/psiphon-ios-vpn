/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import <Foundation/Foundation.h>

@class RACUnit;
@class RACSignal<__covariant ValueType>;
@class RACSubject<ValueType>;
@class UIViewController;

NS_ASSUME_NONNULL_BEGIN

/**
 * Ad controller tag type.
 * @note Values must be unique.
 */
typedef NSString * AdControllerTag NS_STRING_ENUM;

# pragma mark - Ad presentation enum and helper functions

/**
 * AdPresentationStatus used by implementors of `AdControllerWrapperProtocol`.
 * Represents the status of the ad being presented.
 */
#define AdPresentationErrorStateStartingValue 100 // Represents starting value of AdPresentation error states.
typedef NS_ENUM(NSInteger, AdPresentation) {
      /*! @const AdPresentationWillAppear Ad view controller will appear. This is not a terminal state. */
      AdPresentationWillAppear = 1,
      /*! @const AdPresentationDidAppear Ad view controller did appear. This is not a terminal state. */
      AdPresentationDidAppear,
      /*! @const AdPresentationWillDisappear Ad view controller will disappear. This is not a terminal state. */
      AdPresentationWillDisappear,
      /*! @const AdPresentationDidDisappear Ad view controller did disappear. This <b>can</b> be a terminal state. */
      AdPresentationDidDisappear,
      /*! @const AdPresentationDidRewardUser For rewarded video ads only. Emitted once the user has been rewarded.
       * This <b>can</b> be a terminal state. */
      AdPresentationDidRewardUser,

      // Ad presentation error states:
      /*! @const AdPresentationErrorInappropriateState The app is not in the appropriate state to present
       * a particular ad. This is a terminal state.*/
      AdPresentationErrorInappropriateState = AdPresentationErrorStateStartingValue,
      /*! @const AdPresentationErrorNoAdsLoaded No ads are loaded. This is a terminal state. */
      AdPresentationErrorNoAdsLoaded,
      /*! @const AdPresentationErrorFailedToPlay Ad failed to play or show. This is a terminal state. */
      AdPresentationErrorFailedToPlay,
      /*! @const AdPresentationErrorCustomDataNotSet Rewarded video ad custom data not set. This is a terminal state.
       *  This is to be emitted by rewareded video ads that set custom data during presentation.*/
      AdPresentationErrorCustomDataNotSet,
};

/**
 * Returns TRUE if `ap` is one of the error states of AdPresentation, FALSE otherwise.
 */
static inline BOOL adPresentationError(AdPresentation ap) {
    return (ap >= AdPresentationErrorStateStartingValue);
};

/**
 * Returns TRUE if `ap` has a value that indicates ad is present on the screen.
 */
static inline BOOL adBeingPresented(AdPresentation ap) {
    return (ap == AdPresentationWillAppear || ap == AdPresentationDidAppear || ap == AdPresentationWillDisappear);
};

#pragma mark -

FOUNDATION_EXPORT NSErrorDomain const AdControllerWrapperErrorDomain;

/**
 * AdControllerWrapperErrorCode are terminating error emissions from signal returned by ad controller `-loadAd` method.
 */
typedef NS_ERROR_ENUM(AdControllerWrapperErrorDomain, AdControllerWrapperErrorCode) {
    /*! @const AdControllerWrapperErrorAdExpired Ad controller's pre-fetched ad has expired. Once emitted by `-loadAd`,
     * AdManager will load a new ad. */
      AdControllerWrapperErrorAdExpired = 1000,
    /*! @const AdControllerWrapperErrorAdFailedToLoad Ad controller failed to load ad. Once emitted by `-loadAd`,
     * AdManager will load a new ad `AD_LOAD_RETRY_COUNT` times. */
      AdControllerWrapperErrorAdFailedToLoad,
    /*! @const AdControllerWrapperErrorCustomDataNotSet Ad controller failed to load an ad since custom data was
     * missing. Note that this is only emitted by rewarded video ads.*/
      AdControllerWrapperErrorCustomDataNotSet,
};

#pragma mark -

/**
 * AdControllerWrapperProtocol is the protocol used by AdManager to interface with different Ad SDKs or types.
 * A wrapper class implementing this protocol should be created for each Ad type or SDK.
 */
@protocol AdControllerWrapperProtocol

@required

@property (nonatomic, readonly) AdControllerTag tag;

// Should be TRUE if ad is ready to be displayed, FALSE otherwise.
// The value should not change while the ad is being presented, and should only be set to FALSE after
// the ad has been dismissed.
// To avoid unnecessary computation for observers of this property, implementations of this protocol
// should check the current value before setting it.
@property (nonatomic, readonly) BOOL ready;

// presentedAdDismissed is hot infinite signal - emits RACUnit whenever an ad is shown.
// Note: It is assumed that after an emission from this signal, it is safe to load another ad.
@property (nonatomic, readonly) RACSubject<RACUnit *> *presentedAdDismissed;

// presentationStatus is hot infinite signal - emits items of type @(AdPresentation).
@property (nonatomic, readonly) RACSubject<NSNumber *> *presentationStatus;

// Loads ad if none is already loaded. Property `ready` should be TRUE after ad has been loaded (whether or not it
// has already been pre-fetched by the SDK).
// Implementations should handle multiple subscriptions to the returned signal without
// side-effects (even if the ad has already been loaded or is loading).
// Returned signal is expected to terminate with an error when an ad expires or fails to load, with the appropriate
// `AdControllerWrapperErrorCode` error code.
//
// e.g. If the ad has already been loaded, the returned signal should emit AdControllerTag immediately.
// Scheduler: should be subscribed on the main thread.
- (RACSignal<AdControllerTag> *)loadAd;

// Unloads ad if one is loaded. `ready` should be FALSE after the unloading is done.
// Implementations should emit the wrapper's tag after ad is unloaded and then complete.
// Scheduler: should be subscribed on the main thread.
- (RACSignal<AdControllerTag> *)unloadAd;

// Implementations should emit items of type @(AdPresentation), and then complete.
// If there are no ads loaded, returned signal emits @(AdPresentationErrorNoAdsLoaded) and then completes.
- (RACSignal<NSNumber *> *)presentAdFromViewController:(UIViewController *)viewController;

@end

#pragma mark -

@interface AdControllerWrapperHelper : NSObject

/**
 * Same as `+transformAdPresentationToTerminatingSignal:allowOutOfOrderRewardStatus:`, with allowOutOfOrderRewardStatus
 * set to FALSE.
 */
+ (RACSignal<NSNumber *> *)transformAdPresentationToTerminatingSignal:(RACSignal<NSNumber *> *)presentationStatus;

/**
 * Takes non-terminating `presentationStatus` signal that emits items of type @(AdPresentation)
 * and returns a terminating signals.
 *
 * If allowOutOfOrderRewardStatus is set, waits for both @(AdPresentationDidDisappear)
 * and @(AdPresentationDidRewardUser) before completing. Otherwise completes immediately
 * when @(AdPresentationDidDisappear) is emitted by `presentationStatus`.
 *
 * @param presentationStatus Non-terminating signal that emits items of type @(AdPresentation).
 * @param allowOutOfOrderRewardStatus Whether to allow out-of-order emission of @(AdPresentationDidRewardUser) from
 *                                    the `presentationStatus` signal.
 */
+ (RACSignal<NSNumber *> *)transformAdPresentationToTerminatingSignal:(RACSignal<NSNumber *> *)presentationStatus
                                          allowOutOfOrderRewardStatus:(BOOL)allowOutOfOrderRewardStatus;

@end

NS_ASSUME_NONNULL_END
