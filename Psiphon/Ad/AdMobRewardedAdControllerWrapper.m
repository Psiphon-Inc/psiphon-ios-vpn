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

#import "AdMobRewardedAdControllerWrapper.h"
#import <ReactiveObjC/RACReplaySubject.h>
#import <ReactiveObjC/RACUnit.h>
#import <ReactiveObjC/RACCompoundDisposable.h>
#import "Logging.h"
#import "Nullity.h"
#import "NSError+Convenience.h"
#import "Asserts.h"
#import "PsiCashClient.h"
@import GoogleMobileAds;

PsiFeedbackLogType const AdMobRewardedAdControllerWrapperLogType = @"AdMobRewardedAdControllerWrapper";

@interface AdMobRewardedAdControllerWrapper () <GADRewardBasedVideoAdDelegate>

@property (nonatomic, readwrite, assign) BOOL ready;

/** presentedAdDismissed is hot infinite signal - emits RACUnit whenever an ad is presented. */
@property (nonatomic, readwrite, nonnull) RACSubject<RACUnit *> *presentedAdDismissed;

/** presentationStatus is hot infinite signal - emits items of type @(AdPresentation). */
@property (nonatomic, readwrite, nonnull) RACSubject<NSNumber *> *presentationStatus;

// Private Properties.

/** loadStatus is hot non-completing signal - emits the wrapper tag when the ad has been loaded. */
@property (nonatomic, readwrite, nonnull) RACSubject<AdControllerTag> *loadStatus;

/** TRUE if an ad request has been placed and has not finished yet (either failed or succeeded), FALSE otherwise. */
@property (nonatomic, readwrite, assign) BOOL loading;

@property (nonatomic, readonly) NSString *adUnitID;

@end

@implementation AdMobRewardedAdControllerWrapper

@synthesize tag = _tag;

- (instancetype)initWithAdUnitID:(NSString *)adUnitID withTag:(AdControllerTag)tag {
    _tag = tag;
    _loadStatus = [RACSubject subject];
    _adUnitID = adUnitID;
    _ready = FALSE;
    _presentedAdDismissed = [RACSubject subject];
    _presentationStatus = [RACSubject subject];
    _loading = FALSE;
    return self;
}

- (RACSignal<AdControllerTag> *)loadAd {

    AdMobRewardedAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        // Subscribe to load status before loading an ad to prevent race-condition with "adDidLoad" delegate callback.
        RACDisposable *disposable = [weakSelf.loadStatus subscribe:subscriber];

        GADRewardBasedVideoAd *videoAd = [GADRewardBasedVideoAd sharedInstance];

        // Create ad request only if one is not ready or is not loading.
        if (videoAd.isReady) {
            // Manually call the delegate method to re-execute the logic for when an ad is loaded.
            [weakSelf rewardBasedVideoAdDidReceiveAd:videoAd];

        } else if (!weakSelf.loading) {

            weakSelf.loading = TRUE;

            videoAd.delegate = weakSelf;

            GADRequest *request = [GADRequest request];

    #if DEBUG
            request.testDevices = @[@"4a907b319b37ceee4d9970dbb0231ef0"];
    #endif
            [videoAd loadRequest:request withAdUnitID:self.adUnitID];
        }

        return disposable;
    }];
}

- (RACSignal<AdControllerTag> *)unloadAd {

    AdMobRewardedAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        [GADRewardBasedVideoAd sharedInstance].delegate = nil;

        if (weakSelf.ready) {
            weakSelf.ready = FALSE;
        }

        [subscriber sendNext:weakSelf.tag];
        [subscriber sendCompleted];
        return nil;
    }];
}

- (RACSignal<NSNumber *> *)presentAdFromViewController:(UIViewController *)viewController
                                        withCustomData:(NSString *_Nullable)customData {

    AdMobRewardedAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        GADRewardBasedVideoAd *videoAd = [GADRewardBasedVideoAd sharedInstance];

        if (!weakSelf.ready || !videoAd.isReady) {
            [subscriber sendNext:@(AdPresentationErrorNoAdsLoaded)];
            [subscriber sendCompleted];
            return nil;
        }

        if ([Nullity isEmpty:customData]) {
            [subscriber sendNext:@(AdPresentationErrorCustomDataNotSet)];
            [subscriber sendCompleted];
            return nil;
        }

        // Subscribe to presentationStatus before presenting the ad.
        RACDisposable *disposable = [[AdControllerWrapperHelper
          transformAdPresentationToTerminatingSignal:weakSelf.presentationStatus
                         allowOutOfOrderRewardStatus:TRUE]
          subscribe:subscriber];

        [videoAd setCustomRewardString:customData];
        [videoAd presentFromRootViewController:viewController];

        return disposable;
    }];
}

#pragma mark - <GADRewardBasedVideoAdDelegate> status relay

- (void)rewardBasedVideoAd:(GADRewardBasedVideoAd *)rewardBasedVideoAd didRewardUserWithReward:(GADAdReward *)reward {
    LOG_DEBUG(@"User rewarded for ad unit (%@)", self.adUnitID);
    [self.presentationStatus sendNext:@(AdPresentationDidRewardUser)];
}

- (void)rewardBasedVideoAdDidReceiveAd:(GADRewardBasedVideoAd *)rewardBasedVideoAd {

    self.loading = FALSE;

    if (!self.ready) {
        self.ready = TRUE;
    }
    [self.loadStatus sendNext:self.tag];
}

- (void)rewardBasedVideoAd:(GADRewardBasedVideoAd *)rewardBasedVideoAd didFailToLoadWithError:(NSError *)error {

    self.loading = FALSE;

    if (self.ready) {
        self.ready = FALSE;
    }
    [self.loadStatus sendError:[NSError errorWithDomain:AdControllerWrapperErrorDomain
                                                   code:AdControllerWrapperErrorAdFailedToLoad
                                    withUnderlyingError:error]];
}


- (void)rewardBasedVideoAdDidOpen:(GADRewardBasedVideoAd *)rewardBasedVideoAd {
    [self.presentationStatus sendNext:@(AdPresentationWillAppear)];
    [self.presentationStatus sendNext:@(AdPresentationDidAppear)];
}

- (void)rewardBasedVideoAdDidStartPlaying:(GADRewardBasedVideoAd *)rewardBasedVideoAd {
    // Do nothing.
}

- (void)rewardBasedVideoAdDidCompletePlaying:(GADRewardBasedVideoAd *)rewardBasedVideoAd {
    // Do nothing.
}

- (void)rewardBasedVideoAdDidClose:(GADRewardBasedVideoAd *)rewardBasedVideoAd {
    if (self.ready) {
        self.ready = FALSE;
    }


    [self.presentationStatus sendNext:@(AdPresentationWillDisappear)];
    [self.presentationStatus sendNext:@(AdPresentationDidDisappear)];

    [self.presentedAdDismissed sendNext:RACUnit.defaultUnit];

    [PsiFeedbackLogger infoWithType:AdMobRewardedAdControllerWrapperLogType json:
      @{@"event": @"adDidDisappear", @"tag": self.tag}];
}

- (void)rewardBasedVideoAdWillLeaveApplication:(GADRewardBasedVideoAd *)rewardBasedVideoAd {
    // Do nothing.
}

@end
