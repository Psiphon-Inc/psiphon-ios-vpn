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

#import "AdMobInterstitialAdControllerWrapper.h"
#import <ReactiveObjC/NSObject+RACPropertySubscribing.h>
#import <ReactiveObjC/RACDisposable.h>
#import <ReactiveObjC/RACSignal+Operations.h>
#import "RACReplaySubject.h"
#import "NSError+Convenience.h"
#import "RACUnit.h"
#import "Logging.h"
#import "Asserts.h"
#import "AdMobConsent.h"
#import "GADInterstitialDelegate.h"
#import "RACTuple.h"
#import "RelaySubject.h"

PsiFeedbackLogType const AdMobInterstitialAdControllerWrapperLogType = @"AdMobInterstitialAdControllerWrapper";

@interface AdMobInterstitialAdControllerWrapper () <GADInterstitialDelegate>

@property (nonatomic, readwrite, nonnull) BehaviorRelay<NSNumber *> *canPresentOrPresenting;

/** presentedAdDismissed is hot infinite signal - emits RACUnit whenever an ad is presented. */
@property (nonatomic, readwrite, nonnull) RACSubject<RACUnit *> *presentedAdDismissed;

/** presentationStatus is hot infinite signal - emits items of type @(AdPresentation). */
@property (nonatomic, readwrite, nonnull) RACSubject<NSNumber *> *presentationStatus;

// Private properties

// GADInterstitial is a single use object per interstitial shown.
@property (nonatomic, readwrite, nullable) GADInterstitial *interstitial;

/** loadStatus is hot relay subject - emits the wrapper tag when the ad has been loaded. */
@property (nonatomic, readwrite, nonnull) RelaySubject<RACTwoTuple <AdControllerTag, NSError *> *> *loadStatusRelay;

@property (nonatomic, readonly) NSString *adUnitID;

// Set whenever the interstitial failed to load.
// Value is set to nil immediately before submitting a new ad request.
@property (nonatomic, readwrite, nullable) NSError *lastError;

@end

@implementation AdMobInterstitialAdControllerWrapper

@synthesize tag = _tag;

- (instancetype)initWithAdUnitID:(NSString *)adUnitID withTag:(AdControllerTag)tag{
    _tag = tag;
    _loadStatusRelay = [RelaySubject subject];
    _adUnitID = adUnitID;
    _canPresentOrPresenting = [BehaviorRelay behaviorSubjectWithDefaultValue:@(FALSE)];
    _presentedAdDismissed = [RACSubject subject];
    _presentationStatus = [RACSubject subject];
    return self;
}

- (RACSignal<RACTwoTuple<AdControllerTag, NSError *> *> *)loadAd {

    AdMobInterstitialAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        // Subscribe to load status before loading an ad to prevent race-condition with "adDidLoad" delegate callback.
        RACDisposable *disposable = [weakSelf.loadStatusRelay subscribe:subscriber];

        // If interstitial is not initialized, or ad has already been displayed, or last load request failed,
        // initialize interstitial and start loading ad.
        if (!weakSelf.interstitial || weakSelf.interstitial.hasBeenUsed || weakSelf.lastError) {

            // Reset last error status.
            weakSelf.lastError = nil;

            weakSelf.interstitial = [[GADInterstitial alloc] initWithAdUnitID:self.adUnitID];

            if (!weakSelf.interstitial.delegate) {
                weakSelf.interstitial.delegate = weakSelf;
            }

            GADRequest *request = [AdMobConsent createGADRequestWithUserConsentStatus];

#if DEBUG
            request.testDevices = @[ @"4a907b319b37ceee4d9970dbb0231ef0" ];
#endif
            [weakSelf.interstitial loadRequest:request];

        } else if (weakSelf.interstitial.isReady) {

            // Manually call the delegate method to re-execute the logic for when an ad is loaded.
            [weakSelf interstitialDidReceiveAd:weakSelf.interstitial];
        }

        return disposable;
    }];
}

- (RACSignal<RACTwoTuple<AdControllerTag, NSError *> *> *)unloadAd {

    AdMobInterstitialAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        if ([[weakSelf.canPresentOrPresenting first] boolValue]) {
            [weakSelf.canPresentOrPresenting sendNext:@(FALSE)];
        }

        [subscriber sendNext:[RACTwoTuple pack:weakSelf.tag :nil]];
        [subscriber sendCompleted];

        return nil;
    }];
}

- (RACSignal<NSNumber *> *)presentAdFromViewController:(UIViewController *)viewController {

    AdMobInterstitialAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        if (!weakSelf.interstitial.isReady) {
            [subscriber sendNext:@(AdPresentationErrorNoAdsLoaded)];
            [subscriber sendCompleted];
            return nil;
        }

        // Subscribe to presentationStatus before presenting the ad.
        RACDisposable *disposable = [[AdControllerWrapperHelper
          transformAdPresentationToTerminatingSignal:weakSelf.presentationStatus]
          subscribe:subscriber];

        [weakSelf.interstitial presentFromRootViewController:viewController];

        return disposable;
    }];
}

#pragma mark - <GADInterstitialDelegate> status relay

- (void)interstitialDidReceiveAd:(GADInterstitial *)ad {
    if (![[self.canPresentOrPresenting first] boolValue]) {
        [self.canPresentOrPresenting sendNext:@(TRUE)];
    }
    [self.loadStatusRelay sendNext:[RACTwoTuple pack:self.tag :nil]];
}

- (void)interstitial:(GADInterstitial *)ad didFailToReceiveAdWithError:(GADRequestError *)error {
    if ([[self.canPresentOrPresenting first] boolValue]) {
        [self.canPresentOrPresenting sendNext:@(FALSE)];
    }
    self.lastError = error;
    NSError *e = [NSError errorWithDomain:AdControllerWrapperErrorDomain
                                     code:AdControllerWrapperErrorAdFailedToLoad
                      withUnderlyingError:error];

    [self.loadStatusRelay sendNext:[RACTwoTuple pack:self.tag :e]];
}

- (void)interstitialWillPresentScreen:(GADInterstitial *)ad {
    [self.presentationStatus sendNext:@(AdPresentationWillAppear)];
}

- (void)interstitialDidFailToPresentScreen:(GADInterstitial *)ad {
    if ([[self.canPresentOrPresenting first] boolValue]) {
        [self.canPresentOrPresenting sendNext:@(FALSE)];
    }
    [self.presentationStatus sendNext:@(AdPresentationErrorFailedToPlay)];
}

- (void)interstitialWillDismissScreen:(GADInterstitial *)ad {
    [self.presentationStatus sendNext:@(AdPresentationWillDisappear)];
}

- (void)interstitialDidDismissScreen:(GADInterstitial *)ad {
    if ([[self.canPresentOrPresenting first] boolValue]) {
        [self.canPresentOrPresenting sendNext:@(FALSE)];
    }
    [self.presentationStatus sendNext:@(AdPresentationDidDisappear)];
    [self.presentedAdDismissed sendNext:RACUnit.defaultUnit];

    [PsiFeedbackLogger infoWithType:AdMobInterstitialAdControllerWrapperLogType json:
      @{@"event": @"adDidDisappear", @"tag": self.tag}];
}

- (void)interstitialWillLeaveApplication:(GADInterstitial *)ad {
  // Do nothing.
}

@end
