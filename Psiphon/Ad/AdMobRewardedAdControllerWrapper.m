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
#import <ReactiveObjC/RACTuple.h>
#import "Logging.h"
#import "Nullity.h"
#import "NSError+Convenience.h"
#import "Asserts.h"
#import <GoogleMobileAds/GADRewardBasedVideoAdDelegate.h>
#import "AdMobConsent.h"
#import "RelaySubject.h"
#import "Psiphon-Swift.h"

PsiFeedbackLogType const AdMobRewardedAdControllerWrapperLogType = @"AdMobRewardedAdControllerWrapper";

@interface AdMobRewardedAdControllerWrapper () <GADRewardBasedVideoAdDelegate>

@property (nonatomic, readwrite, nonnull) BehaviorRelay<NSNumber *> *adLoadStatus;

/** presentedAdDismissed is hot infinite signal - emits RACUnit whenever an ad is presented. */
@property (nonatomic, readwrite, nonnull) RACSubject<RACUnit *> *presentedAdDismissed;

/** presentationStatus is hot infinite signal - emits items of type @(AdPresentation). */
@property (nonatomic, readwrite, nonnull) RACSubject<NSNumber *> *presentationStatus;

// Private Properties.

/** loadStatus is hot relay subject - emits the wrapper tag when the ad has been loaded. */
@property (nonatomic, readwrite, nonnull) RelaySubject<RACTwoTuple<AdControllerTag, NSError *> *> *loadStatusRelay;

@property (nonatomic, readonly) NSString *adUnitID;

@end

@implementation AdMobRewardedAdControllerWrapper

@synthesize tag = _tag;

- (instancetype)initWithAdUnitID:(NSString *)adUnitID withTag:(AdControllerTag)tag {
    _tag = tag;
    _loadStatusRelay = [RelaySubject subject];
    _adUnitID = adUnitID;
    _adLoadStatus = [BehaviorRelay behaviorSubjectWithDefaultValue:@(AdLoadStatusNone)];
    _presentedAdDismissed = [RACSubject subject];
    _presentationStatus = [RACSubject subject];
    return self;
}

- (AdFormat)adFormat {
    return AdFormatRewardedVideo;
}

- (RACSignal<RACTwoTuple<AdControllerTag, NSError *> *> *)loadAd {

    AdMobRewardedAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        RACCompoundDisposable *compoundDisposable = [[RACCompoundDisposable alloc] init];

        [SwiftDelegate.bridge getCustomRewardData:^(NSString * _Nullable customData) {
            if ([Nullity isEmpty:customData]) {
                NSError *e = [NSError errorWithDomain:AdControllerWrapperErrorDomain
                                                 code:AdControllerWrapperErrorCustomDataNotSet];
                [subscriber sendNext:[RACTwoTuple pack:self.tag :e]];
                return;
            }

            // Subscribe to load status before loading an ad to prevent
            // race-condition with ad"adDidLoad" delegate callback.
            [compoundDisposable addDisposable:[weakSelf.loadStatusRelay subscribe:subscriber]];

            GADRewardBasedVideoAd *videoAd = [GADRewardBasedVideoAd sharedInstance];
            if (!videoAd.delegate) {
                videoAd.delegate = weakSelf;
            }

            // Create ad request only if one is not ready.
            if (videoAd.isReady) {
                // Manually call the delegate method to re-execute the logic
                // for when an ad is loaded.
                [weakSelf rewardBasedVideoAdDidReceiveAd:videoAd];

            } else {
                [self.adLoadStatus accept:@(AdLoadStatusInProgress)];

                GADRequest *request = [AdMobConsent createGADRequestWithUserConsentStatus];
#if DEBUG
                request.testDevices = @[@"4a907b319b37ceee4d9970dbb0231ef0"];
#endif
                [videoAd setCustomRewardString:customData];
                [videoAd loadRequest:request withAdUnitID:self.adUnitID];
            }
        }];

        return compoundDisposable;
    }];
}

- (RACSignal<RACTwoTuple<AdControllerTag, NSError *> *> *)unloadAd {

    AdMobRewardedAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        [weakSelf.adLoadStatus accept:@(AdLoadStatusNone)];

        [subscriber sendNext:[RACTwoTuple pack:weakSelf.tag :nil]];
        [subscriber sendCompleted];
        return nil;
    }];
}

- (RACSignal<NSNumber *> *)presentAdFromViewController:(UIViewController *)viewController {

    AdMobRewardedAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        GADRewardBasedVideoAd *videoAd = [GADRewardBasedVideoAd sharedInstance];

        if (!videoAd.isReady) {
            [subscriber sendNext:@(AdPresentationErrorNoAdsLoaded)];
            [subscriber sendCompleted];
            return nil;
        }

        // Subscribe to presentationStatus before presenting the ad.
        RACDisposable *disposable = [[AdControllerWrapperHelper
          transformAdPresentationToTerminatingSignal:weakSelf.presentationStatus
                         allowOutOfOrderRewardStatus:TRUE]
          subscribe:subscriber];

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
    [self.adLoadStatus accept:@(AdLoadStatusDone)];
    [self.loadStatusRelay accept:[RACTwoTuple pack:self.tag :nil]];
}

- (void)rewardBasedVideoAd:(GADRewardBasedVideoAd *)rewardBasedVideoAd didFailToLoadWithError:(NSError *)error {
    [self.adLoadStatus accept:@(AdLoadStatusError)];

    NSError *e = [NSError errorWithDomain:AdControllerWrapperErrorDomain
                                     code:AdControllerWrapperErrorAdFailedToLoad
                      withUnderlyingError:error];
    [self.loadStatusRelay accept:[RACTwoTuple pack:self.tag :e]];
}

- (void)rewardBasedVideoAdDidOpen:(GADRewardBasedVideoAd *)rewardBasedVideoAd {
    [self.presentationStatus sendNext:@(AdPresentationWillAppear)];
    [self.presentationStatus sendNext:@(AdPresentationDidAppear)];
}

- (void)rewardBasedVideoAdDidStartPlaying:(GADRewardBasedVideoAd *)rewardBasedVideoAd {
    [self.adLoadStatus accept:@(AdLoadStatusNone)];
    // Do nothing.
}

- (void)rewardBasedVideoAdDidCompletePlaying:(GADRewardBasedVideoAd *)rewardBasedVideoAd {
    // Do nothing.
}

- (void)rewardBasedVideoAdDidClose:(GADRewardBasedVideoAd *)rewardBasedVideoAd {
    // Do nothing.

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
