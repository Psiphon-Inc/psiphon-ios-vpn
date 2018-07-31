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

#import <Foundation/Foundation.h>
#import <mopub-ios-sdk/MPInterstitialAdController.h>
#import <mopub-ios-sdk/MoPub.h>
#import <mopub-ios-sdk/MPRewardedVideo.h>

@class RACUnit;
@class RACSignal<__covariant ValueType>;
@class RACSubject<ValueType>;
@class RACReplaySubject<ValueType>;
@class InterstitialAdControllerWrapper;
@class RewardedAdControllerWrapper;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - AdControllerWrapperProtocol definition

/**
 * Ad controller tag type.
 * @note Values must be unique.
 */
typedef NSString * AdControllerTag NS_STRING_ENUM;

/**
 * AdPresentationStatus used by implementors of `AdControllerWrapperProtocol`.
 * Represents the status of the ad being presented.
 */
typedef NS_ENUM(NSInteger, AdPresentation) {
    AdPresentationWillAppear = 1,
    AdPresentationDidAppear,
    AdPresentationWillDisappear,
    AdPresentationDidDisappear,

    // Ad presentation error states:
    AdPresentationErrorNoAdsLoaded,
    AdPresentationErrorFailedToPlay,  // Used only for rewarded videos.
    AdPresentationErrorCustomDataNotSet  // Used only for rewarded videos.
};

FOUNDATION_EXPORT NSErrorDomain const AdControllerWrapperErrorDomain;

typedef NS_ERROR_ENUM(AdControllerWrapperErrorDomain, AdControllerWrapperErrorCode) {
    AdControllerWrapperErrorAdExpired = 1000,
    AdControllerWrapperErrorAdFailedToLoad,
};

/**
 * AdControllerWrapperProtocol is the protocol used by AdManager to interface with different Ad SDKs or types.
 * A wrapper class implementing this protocol should be created for each Ad type or SDK.
 */
@protocol AdControllerWrapperProtocol

@required

// Debugging meta-data.
@property (nonatomic, readonly) AdControllerTag tag;

// Should be TRUE if ad is ready to be displayed, FALSE otherwise.
// To avoid unnecessary computation for observers of this property, implementations of this protocol
// should check the current value before setting it.
@property (nonatomic, readonly) BOOL ready;

// adPresented is hot infinite signal - emits RACUnit whenever an ad is shown.
@property (nonatomic, readonly) RACSubject<RACUnit *> *adPresented;

// presentationStatus is hot infinite signal - emits items of type @(AdPresentation).
@property (nonatomic, readonly) RACSubject<NSNumber *> *presentationStatus;

// Implementations should handle multiple subscriptions to the returned signal, even if the ad has already been loaded.
- (RACSignal<NSString *> *)loadAd;

// Implementations should emit the wrapper's tag after ad is unloaded and then complete.
- (RACSignal<NSString *> *)unloadAd;

// Implementations should emit items of type @(AdPresentation), and complete when the ad has been dismissed.
// If there are no ads loaded, returned signal emits @(AdPresentationErrorNoAdsLoaded) and then completes.
- (RACSignal<NSNumber *> *)presentAdFromViewController:(UIViewController *)viewController;

@end


#pragma mark - AdManager class

// List of all AdControllerTag objects.
FOUNDATION_EXPORT AdControllerTag const AdControllerTagUntunneledInterstitial;
FOUNDATION_EXPORT AdControllerTag const AdControllerTagUntunneledRewardedVideo;
FOUNDATION_EXPORT AdControllerTag const AdControllerTagTunneledRewardedVideo;

@interface AdManager : NSObject

/**
 * Infinite signal that emits @(TRUE) if an is currently being displayed, @(FALSE) otherwise.
 * The subject may emit duplicate state.
 */
@property (nonatomic, readonly) RACReplaySubject<NSNumber *> *adIsShowing;

/**
 * TRUE when the untunneled interstitial is ready to be presented.
 */
@property (nonatomic, readonly) BOOL untunneledInterstitialIsReady;

/**
 * TRUE when tunneled or untunneled rewarded video is ready to be presented.
 */
@property (nonatomic, readonly) BOOL rewardedVideoIsReady;

+ (instancetype)sharedInstance;

/**
 * Initializes the Ads SDK.
 * This should be called during the apps difFinishLaunchingWithOptions: delegate callback.
 */
- (void)initializeAdManager;

/**
 * Sets the custom data for the rewarded video ads to include in the server-to-server callback.
 * If custom data is not set, rewarded video ads will not present the pre-fetched ad.
 * This method can be called at anytime to set or change the custom data sent.
 */
- (void)setRewardedVideoCustomData:(NSString *)data;

/**
 * Presents untunneled interstitial if app is in the appropriate state, and an interstitial ad has already been loaded.
 *
 * If ad cannot be presented due to inappropriate app state, returned signal completes immediately.
 *
 * If the app state is appropriate for displaying an ad, but there's an underlying error,
 * one of the errors states of @(AdPresentation) will be emitted (enums starting with AdPresentationError_)
 * and then the signal will complete.
 *
 * If the add is ready to be presented, the signal will start by emitting the following states in order:
 *  AdPresentationWillAppear -> AdPresentationDidAppear -> AdPresentationWillDisappear -> AdPresentationDidDisappear
 * after which the signal will complete.
 */
- (RACSignal<NSNumber *> *)presentInterstitialOnViewController:(UIViewController *)viewController;

/**
 * Presents tunneled or untunneled rewarded video ad if app is in the appropriate state and the rewarded video
 * ad has been loaded.
 *
 * If ad cannot be presented due to inappropriate app state, returned signal completes immediately.
 *
 * If the app state is appropriate for displaying an ad, but there's an underlying error,
 * one of the errors states of @(AdPresentation) will be emitted (enums starting with AdPresentationError_)
 * and then the signal will complete.
 *
 * If the add is ready to be presented, the signal will start by emitting the following states in order:
 *  AdPresentationWillAppear -> AdPresentationDidAppear -> AdPresentationWillDisappear -> AdPresentationDidDisappear
 * after which the signal will complete.
 */
- (RACSignal<NSNumber *> *)presentRewardedVideoOnViewController:(UIViewController *)viewController;

@end

NS_ASSUME_NONNULL_END
