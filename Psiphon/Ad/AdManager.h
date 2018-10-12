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
#import "AdControllerWrapper.h"

@class RACSignal<__covariant ValueType>;
@class RACReplaySubject<ValueType>;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - AdManager class

// List of all AdControllerTag objects.
FOUNDATION_EXPORT AdControllerTag const AdControllerTagUntunneledInterstitial;
FOUNDATION_EXPORT AdControllerTag const AdControllerTagUntunneledRewardedVideo;
FOUNDATION_EXPORT AdControllerTag const AdControllerTagTunneledRewardedVideo;

@interface AdManager : NSObject

/**
 * Infinite signal that emits @(TRUE) if an is currently being displayed, @(FALSE) otherwise.
 * Replay subject starts with initial value of @(FALSE) during `-initializeAdManager`.
 * The subject may emit non-unique states.
 * @scheduler Events are delivered on the main thread.
 */
@property (nonatomic, readonly) RACReplaySubject<NSNumber *> *adIsShowing;

/**
 * Emits @(TRUE) when the untunneled interstitial is ready to be presented.
 * Emits @(FALSE) when app conditions are such that the ad cannot be presented, this is regardless of whether the
 * ad has been loaded.
 * Subject initially has default value @(FALSE).
 * @scheduler Events are delivered on the main thread.
 */
@property (nonatomic, readonly) RACReplaySubject<NSNumber *> *untunneledInterstitialCanPresent;

/**
 * Emits @(TRUE) when tunneled or untunneled rewarded video is ready to be presented.
 * Emits @(FALSE) when app conditions are such that the ad cannot be presented, this is regardless of whether the
 * ad has been loaded.
 * Subject initially has default value @(FALSE).
 * @scheduler Events are delivered on the main thread.
 */
@property (nonatomic, readonly) RACReplaySubject<NSNumber *> *rewardedVideoCanPresent;

+ (instancetype)sharedInstance;

/**
 * Initializes the Ads SDK.
 * This should be called during the apps difFinishLaunchingWithOptions: delegate callback.
 */
- (void)initializeAdManager;

/**
 * Returns a signal that upon subscriptions presents ad (if one is already loaded).
 * Returned signal emits items of type @(AdPresentation), and completes immediately after the presented ad is dismissed,
 * or after emission of an AdPresentation error state.
 *
 * If ad cannot be presented due to inappropriate app state, returned signal completes immediately.
 *
 * If the app state is appropriate for displaying an ad, but there's an underlying error,
 * one of the errors states of @(AdPresentation) will be emitted (enums starting with AdPresentationError_)
 * and then the signal will complete.
 *
 * @return Returned signal emits items of @(AdPresentation) or nothing. Always completes.
 *
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
 * @param viewController View controller to display ad on top of.
 * @param customData Optional custom data to include in the ad service server-to-server callback.
 *
 * @return Returned signal emits items of type @(AdPresentation) or nothing. Always completes.
 */
- (RACSignal<NSNumber *> *)presentRewardedVideoOnViewController:(UIViewController *)viewController
                                                 withCustomData:(NSString *_Nullable)customData;

@end

NS_ASSUME_NONNULL_END
