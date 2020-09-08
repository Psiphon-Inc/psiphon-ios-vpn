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
#import "RelaySubject.h"
#import "Psiphon-Swift.h"

PsiFeedbackLogType const AdMobRewardedAdControllerWrapperLogType = @"AdMobRewardedAdControllerWrapper";

@interface AdMobRewardedAdControllerWrapper () <GADRewardedAdDelegate>

@property (nonatomic, readwrite, nonnull) BehaviorRelay<NSNumber *> *adLoadStatus;

/** presentedAdDismissed is hot infinite signal - emits RACUnit whenever an ad is presented. */
@property (nonatomic, readwrite, nonnull) RACSubject<RACUnit *> *presentedAdDismissed;

/** presentationStatus is hot infinite signal - emits items of type @(AdPresentation). */
@property (nonatomic, readwrite, nonnull) RACSubject<NSNumber *> *presentationStatus;

// Private Properties.

/** loadStatus is hot relay subject - emits the wrapper tag when the ad has been loaded. */
@property (nonatomic, readwrite, nonnull) RelaySubject<RACTwoTuple<AdControllerTag, NSError *> *> *loadStatusRelay;

@property (nonatomic, readonly) NSString *adUnitID;

@property (nonatomic, readwrite, nullable) GADRewardedAd* rewardedAd;

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
    _rewardedAd = nil;
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
            
            AdMobRewardedAdControllerWrapper *__strong strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            
            if ([Nullity isEmpty:customData]) {
                NSError *e = [NSError errorWithDomain:AdControllerWrapperErrorDomain
                                                 code:AdControllerWrapperErrorCustomDataNotSet];
                [subscriber sendNext:[RACTwoTuple pack:self.tag :e]];
                return;
            }

            // Subscribe to load status before loading an ad to prevent
            // race-condition with ad"adDidLoad" delegate callback.
            [compoundDisposable addDisposable:[weakSelf.loadStatusRelay subscribe:subscriber]];

            // Create ad request only if one is not ready.
            if (strongSelf.rewardedAd != nil && strongSelf.rewardedAd.isReady) {
                [strongSelf handleAdLoadedSuccessfully];

            } else {
                [self.adLoadStatus accept:@(AdLoadStatusInProgress)];
                
                strongSelf.rewardedAd = [[GADRewardedAd alloc]
                                         initWithAdUnitID:strongSelf.adUnitID];
                
                GADRequest *request = [AdConsent.sharedInstance makeGADRequestWithNPA];
                
                GADServerSideVerificationOptions *ssvOptions = [[GADServerSideVerificationOptions alloc] init];
                ssvOptions.customRewardString = customData;
                [strongSelf.rewardedAd setServerSideVerificationOptions:ssvOptions];
                
                [strongSelf.rewardedAd loadRequest:request completionHandler:^(GADRequestError * _Nullable error) {
                    AdMobRewardedAdControllerWrapper *__strong strongSelf = weakSelf;
                    if (strongSelf == nil) {
                        return;
                    }
                    
                    if (error == nil) {
                        // Ad loaded successfully.
                        [strongSelf handleAdLoadedSuccessfully];
                        
                    } else {
                        // Ad failed to load.
                        [strongSelf.adLoadStatus accept:@(AdLoadStatusError)];
                        NSError *e = [NSError errorWithDomain:AdControllerWrapperErrorDomain
                                                         code:AdControllerWrapperErrorAdFailedToLoad
                                          withUnderlyingError:error];
                        [strongSelf.loadStatusRelay accept:[RACTwoTuple pack:self.tag :e]];
                    }
                    
                    
                }];
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
        
        AdMobRewardedAdControllerWrapper *__strong strongSelf = weakSelf;
        if (strongSelf == nil) {
            return nil;
        }

        if (!(strongSelf.rewardedAd != nil && strongSelf.rewardedAd.isReady) ||
            viewController.beingDismissed
        ){
            [subscriber sendNext:@(AdPresentationErrorNoAdsLoaded)];
            [subscriber sendCompleted];
            return nil;
        }

        // Check if viewController passed in is being dismissed before
        // presenting the ad.
        // This check should be done regardless of the SDK.
        if (viewController.beingDismissed) {
            [subscriber sendNext:@(AdPresentationErrorFailedToPlay)];
            [subscriber sendCompleted];
            return nil;
        }

        // Subscribe to presentationStatus before presenting the ad.
        RACDisposable *disposable = [[AdControllerWrapperHelper
          transformAdPresentationToTerminatingSignal:weakSelf.presentationStatus
                         allowOutOfOrderRewardStatus:TRUE]
          subscribe:subscriber];
        
        [strongSelf.rewardedAd presentFromRootViewController:viewController
                                                    delegate:strongSelf];

        return disposable;
    }];
}

- (void)handleAdLoadedSuccessfully {
    [self.adLoadStatus accept:@(AdLoadStatusDone)];
    [self.loadStatusRelay accept:[RACTwoTuple pack:self.tag :nil]];
}

#pragma mark - <GADRewardBasedVideoAdDelegate> status relay

- (void)rewardedAd:(GADRewardedAd *)rewardedAd userDidEarnReward:(GADAdReward *)reward {
    LOG_DEBUG(@"User rewarded for ad unit (%@)", self.adUnitID);
    [self.presentationStatus sendNext:@(AdPresentationDidRewardUser)];
}

- (void)rewardedAdDidPresent:(GADRewardedAd *)rewardedAd {
    [self.adLoadStatus accept:@(AdLoadStatusNone)];

    [self.presentationStatus sendNext:@(AdPresentationWillAppear)];
    [self.presentationStatus sendNext:@(AdPresentationDidAppear)];
}

- (void)rewardedAd:(GADRewardedAd *)rewardedAd didFailToPresentWithError:(NSError *)error {
    [self.adLoadStatus accept:@(AdLoadStatusNone)];
    [self.presentationStatus sendNext:@(AdPresentationErrorFailedToPlay)];
}

- (void)rewardedAdDidDismiss:(GADRewardedAd *)rewardedAd {
    [self.presentationStatus sendNext:@(AdPresentationWillDisappear)];
    [self.presentationStatus sendNext:@(AdPresentationDidDisappear)];

    [self.presentedAdDismissed sendNext:RACUnit.defaultUnit];

    [PsiFeedbackLogger infoWithType:AdMobRewardedAdControllerWrapperLogType json:
      @{@"event": @"adDidDisappear", @"tag": self.tag}];
}

@end
