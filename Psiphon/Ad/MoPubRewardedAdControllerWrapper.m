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

#import <ReactiveObjC/RACReplaySubject.h>
#import <ReactiveObjC/RACUnit.h>
#import <ReactiveObjC/RACCompoundDisposable.h>
#import "MoPubRewardedAdControllerWrapper.h"
#import "Asserts.h"
#import "NSError+Convenience.h"
#import "Logging.h"
#import "Nullity.h"
#import "PsiCashClient.h"
#import "RelaySubject.h"


PsiFeedbackLogType const MoPubRewardedAdControllerWrapperLogType = @"MoPubRewardedAdControllerWrapper";

@interface MoPubRewardedAdControllerWrapper () <MPRewardedVideoDelegate>

@property (nonatomic, readwrite, nonnull) BehaviorRelay<NSNumber *> *canPresentOrPresenting;

/** presentedAdDismissed is hot infinite signal - emits RACUnit whenever an ad is presented. */
@property (nonatomic, readwrite, nonnull) RACSubject<RACUnit *> *presentedAdDismissed;

/** presentationStatus is hot infinite signal - emits items of type @(AdPresentation). */
@property (nonatomic, readwrite, nonnull) RACSubject<NSNumber *> *presentationStatus;

// Private Properties.

/** loadStatus is hot relay subject - emits the wrapper tag when the ad has been loaded. */
@property (nonatomic, readwrite, nonnull) RelaySubject<RACTwoTuple<AdControllerTag, NSError *> *> *loadStatusRelay;

@property (nonatomic, readonly) NSString *adUnitID;

@end

@implementation MoPubRewardedAdControllerWrapper

@synthesize tag = _tag;

- (instancetype)initWithAdUnitID:(NSString *)adUnitID withTag:(AdControllerTag)tag {
    _tag = tag;
    _loadStatusRelay = [RelaySubject subject];
    _adUnitID = adUnitID;
    _canPresentOrPresenting = [BehaviorRelay behaviorSubjectWithDefaultValue:@(FALSE)];
    _presentedAdDismissed = [RACSubject subject];
    _presentationStatus = [RACSubject subject];
    return self;
}

- (void)dealloc {
    [MPRewardedVideo removeDelegate:self];
}

- (RACSignal<RACTwoTuple<AdControllerTag, NSError *> *> *)loadAd {

    MoPubRewardedAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        RACDisposable *disposable = [weakSelf.loadStatusRelay subscribe:subscriber];

        [MPRewardedVideo setDelegate:weakSelf forAdUnitId:weakSelf.adUnitID];
        [MPRewardedVideo loadRewardedVideoAdWithAdUnitID:weakSelf.adUnitID withMediationSettings:nil];

        return disposable;
    }];
}

- (RACSignal<RACTwoTuple<AdControllerTag, NSError *> *> *)unloadAd {

    MoPubRewardedAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {
        // Unlike interstitials, MoPub SDK doesn't provide a way to destroy the pre-fetched rewarded video ads.

        if ([[weakSelf.canPresentOrPresenting first] boolValue]) {
            [weakSelf.canPresentOrPresenting sendNext:@(FALSE)];
        }

        [subscriber sendNext:[RACTwoTuple pack:weakSelf.tag :nil]];
        [subscriber sendCompleted];
        return nil;
    }];
}

- (RACSignal<NSNumber *> *)presentAdFromViewController:(UIViewController *)viewController {

    MoPubRewardedAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        // Should not try to present an ad, unless `hasAdAvailableForAdUnitID:` returns True.
        if (![MPRewardedVideo hasAdAvailableForAdUnitID:self.adUnitID]) {
            [subscriber sendNext:@(AdPresentationErrorNoAdsLoaded)];
            [subscriber sendCompleted];
            return nil;
        }

        NSString *_Nullable customData = [[PsiCashClient sharedInstance] rewardedVideoCustomData];
        if ([Nullity isEmpty:customData]) {
            [subscriber sendNext:@(AdPresentationErrorCustomDataNotSet)];
            [subscriber sendCompleted];
            return nil;
        }

        NSArray<MPRewardedVideoReward *> *rewards = [MPRewardedVideo availableRewardsForAdUnitID:self.adUnitID];

        // We're only expecting one reward.
        PSIAssert(rewards.count == 1);

        // Subscribe to presentationStatus before presenting the ad.
        RACDisposable *disposable = [[AdControllerWrapperHelper
          transformAdPresentationToTerminatingSignal:weakSelf.presentationStatus
                         allowOutOfOrderRewardStatus:FALSE]
          subscribe:subscriber];

        // Selects the first reward only, since we're only expecting one type of reward for now.
        [MPRewardedVideo presentRewardedVideoAdForAdUnitID:self.adUnitID
                                        fromViewController:viewController
                                                withReward:rewards[0]
                                                customData:customData];

        return disposable;
    }];
}

#pragma mark - <MPRewardedVideoDelegate> status relay

- (void)rewardedVideoAdDidLoadForAdUnitID:(NSString *)adUnitID {
    if (self.adUnitID != adUnitID) {
        return;
    }
    if (![[self.canPresentOrPresenting first] boolValue]) {
        [self.canPresentOrPresenting sendNext:@(TRUE)];
    }
    [self.loadStatusRelay sendNext:[RACTwoTuple pack:self.tag :nil]];
}

- (void)rewardedVideoAdDidFailToLoadForAdUnitID:(NSString *)adUnitID error:(NSError *)error {
    if (self.adUnitID != adUnitID) {
        return;
    }
    if ([[self.canPresentOrPresenting first] boolValue]) {
        [self.canPresentOrPresenting sendNext:@(FALSE)];
    }

    NSError *e = [NSError errorWithDomain:AdControllerWrapperErrorDomain
                                     code:AdControllerWrapperErrorAdFailedToLoad
                      withUnderlyingError:error];

    [self.loadStatusRelay sendNext:[RACTwoTuple pack:self.tag :e]];
}

- (void)rewardedVideoAdDidExpireForAdUnitID:(NSString *)adUnitID {
    if (self.adUnitID != adUnitID) {
        return;
    }
    if ([[self.canPresentOrPresenting first] boolValue]) {
        [self.canPresentOrPresenting sendNext:@(FALSE)];
    }

    NSError *e = [NSError errorWithDomain:AdControllerWrapperErrorDomain
                                     code:AdControllerWrapperErrorAdExpired];

    [self.loadStatusRelay sendNext:[RACTwoTuple pack:self.tag :e]];
}

- (void)rewardedVideoAdDidFailToPlayForAdUnitID:(NSString *)adUnitID error:(NSError *)error {
    if (self.adUnitID != adUnitID) {
        return;
    }

    if ([[self.canPresentOrPresenting first] boolValue]) {
        [self.canPresentOrPresenting sendNext:@(FALSE)];
    }

    [self.presentationStatus sendNext:@(AdPresentationErrorFailedToPlay)];
}

- (void)rewardedVideoAdWillAppearForAdUnitID:(NSString *)adUnitID {
    if (self.adUnitID != adUnitID) {
        return;
    }
    [self.presentationStatus sendNext:@(AdPresentationWillAppear)];
}

- (void)rewardedVideoAdDidAppearForAdUnitID:(NSString *)adUnitID {
    if (self.adUnitID != adUnitID) {
        return;
    }
    [self.presentationStatus sendNext:@(AdPresentationDidAppear)];
}

- (void)rewardedVideoAdWillDisappearForAdUnitID:(NSString *)adUnitID {
    if (self.adUnitID != adUnitID) {
        return;
    }
    [self.presentationStatus sendNext:@(AdPresentationWillDisappear)];
}

- (void)rewardedVideoAdDidDisappearForAdUnitID:(NSString *)adUnitID {
    if (self.adUnitID != adUnitID) {
        return;
    }

    if ([[self.canPresentOrPresenting first] boolValue]) {
        [self.canPresentOrPresenting sendNext:@(FALSE)];
    }

    // Since MoPub SDK states that `rewardedVideoAdShouldRewardForAdUnitID:reward:` delegate callback will not be
    // called if server-side rewarding is enabled, we will emit `AdPresentationDidRewardUser` here immediately.
    [self.presentationStatus sendNext:@(AdPresentationDidRewardUser)];

    [self.presentationStatus sendNext:@(AdPresentationDidDisappear)];

    [self.presentedAdDismissed sendNext:RACUnit.defaultUnit];

    [PsiFeedbackLogger infoWithType:MoPubRewardedAdControllerWrapperLogType json:
      @{@"event": @"adDidDisappear", @"tag": self.tag}];
}

//- (void)rewardedVideoAdDidReceiveTapEventForAdUnitID:(NSString *)adUnitID {
//    if (self.adUnitID != adUnitID) {
//        return;
//    }
//}

//- (void)rewardedVideoAdWillLeaveApplicationForAdUnitID:(NSString *)adUnitID {
//}

// From MoPub Docs: https://developers.mopub.com/docs/ui/apps/rewarded-server-side-setup/
//
// IMPORTANT: After updating an ad unit to use server-side rewarding, MoPub will no longer provide a client-side
// reward callback in the SDK. If you have older versions of your app that use client-side rewarding, please
// create a new ad unit for server-side rewarding.
//
- (void)rewardedVideoAdShouldRewardForAdUnitID:(NSString *)adUnitID reward:(MPRewardedVideoReward *)reward {
    if (self.adUnitID != adUnitID) {
        return;
    }
    // DO NOT rely on this callback.
    LOG_DEBUG(@"User rewarded for ad unit (%@)", adUnitID);
}

@end
