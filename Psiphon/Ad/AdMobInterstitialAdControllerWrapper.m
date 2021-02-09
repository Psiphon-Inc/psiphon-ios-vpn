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
#import "RACTuple.h"
#import "RelaySubject.h"
#import "Psiphon-Swift.h"
@import GoogleMobileAds;

PsiFeedbackLogType const AdMobInterstitialAdControllerWrapperLogType = @"AdMobInterstitialAdControllerWrapper";

@interface AdMobInterstitialAdControllerWrapper () <GADFullScreenContentDelegate>

@property (nonatomic, readwrite, nonnull) BehaviorRelay<NSNumber *> *adLoadStatus;

/** presentedAdDismissed is hot infinite signal - emits RACUnit whenever an ad is presented. */
@property (nonatomic, readwrite, nonnull) RACSubject<RACUnit *> *presentedAdDismissed;

/** presentationStatus is hot infinite signal - emits items of type @(AdPresentation). */
@property (nonatomic, readwrite, nonnull) RACSubject<NSNumber *> *presentationStatus;

// Private properties

// When not nil, an ad is already loaded and is ready to be presented.
@property (nonatomic, readwrite, nullable) GADInterstitialAd *interstitialAd;

/** loadStatus is hot relay subject - emits the wrapper tag when the ad has been loaded. */
@property (nonatomic, readwrite, nonnull) RelaySubject<RACTwoTuple <AdControllerTag, NSError *> *> *loadStatusRelay;

@property (nonatomic, readonly) NSString *adUnitID;

@end

@implementation AdMobInterstitialAdControllerWrapper

@synthesize tag = _tag;

- (instancetype)initWithAdUnitID:(NSString *)adUnitID withTag:(AdControllerTag)tag{
    _tag = tag;
    _loadStatusRelay = [RelaySubject subject];
    _adUnitID = adUnitID;
    _adLoadStatus = [BehaviorRelay behaviorSubjectWithDefaultValue:@(AdLoadStatusNone)];
    _presentedAdDismissed = [RACSubject subject];
    _presentationStatus = [RACSubject subject];
    return self;
}

- (AdFormat)adFormat {
    return AdFormatInterstitial;
}

- (RACSignal<RACTwoTuple<AdControllerTag, NSError *> *> *)loadAd {

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        if ([NSThread isMainThread] == FALSE) {
            @throw [NSException exceptionWithName:@"NotOnMainThread"
                                           reason:@"Expected the call to be on the main thread"
                                         userInfo:nil];
        }

        RACDisposable *disposable = [self.loadStatusRelay subscribe:subscriber];

        // If an ad is already loaded, re-emits ad load status done message.
        if (self.interstitialAd != nil) {

            [self.adLoadStatus accept:@(AdLoadStatusDone)];
            [self.loadStatusRelay accept:[RACTwoTuple pack:self.tag :nil]];

            return disposable;

        }

        [self.adLoadStatus accept:@(AdLoadStatusInProgress)];

        GADRequest *request = [AdConsent.sharedInstance makeGADRequestWithNPA];

        // The load method gets called when ad loading succeeds or fails.
        [GADInterstitialAd loadWithAdUnitID:self.adUnitID
                                    request:request
                          completionHandler:^(GADInterstitialAd * _Nullable interstitialAd, NSError * _Nullable error) {

            if (error != nil) {

                NSError *e = [NSError errorWithDomain:AdControllerWrapperErrorDomain
                                                 code:AdControllerWrapperErrorAdFailedToLoad
                                  withUnderlyingError:error];

                [self.loadStatusRelay accept:[RACTwoTuple pack:self.tag :e]];
                [self.adLoadStatus accept:@(AdLoadStatusError)];

                return;

            }

            self.interstitialAd = interstitialAd;
            self.interstitialAd.fullScreenContentDelegate = self;

            // Relays that the ad was loaded successfully.
            [self.adLoadStatus accept:@(AdLoadStatusDone)];
            [self.loadStatusRelay accept:[RACTwoTuple pack:self.tag :nil]];

        }];

        return disposable;

    }];

}

- (RACSignal<RACTwoTuple<AdControllerTag, NSError *> *> *)unloadAd {

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        if ([NSThread isMainThread] == FALSE) {
            @throw [NSException exceptionWithName:@"NotOnMainThread"
                                           reason:@"Expected the call to be on the main thread"
                                         userInfo:nil];
        }

        self.interstitialAd = nil;

        [self.adLoadStatus accept:@(AdLoadStatusNone)];

        [subscriber sendNext:[RACTwoTuple pack:self.tag :nil]];
        [subscriber sendCompleted];

        return nil;

    }];

}

- (RACSignal<NSNumber *> *)presentAdFromViewController:(UIViewController *)viewController {

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        if ([NSThread isMainThread] == FALSE) {
            @throw [NSException exceptionWithName:@"NotOnMainThread"
                                           reason:@"Expected the call to be on the main thread"
                                         userInfo:nil];
        }

        if (self.interstitialAd == nil) {
            [subscriber sendNext:@(AdPresentationErrorNoAdsLoaded)];
            [subscriber sendCompleted];
            return nil;
        }

        NSError *error = nil;
        BOOL canPresent = [self.interstitialAd
                           canPresentFromRootViewController:viewController
                           error:&error];

        if (canPresent == FALSE) {
            [subscriber sendNext:@(AdPresentationErrorNoAdsLoaded)];
            [subscriber sendCompleted];
            return nil;
        }

        // Subscribe to presentationStatus before presenting the ad.
        RACDisposable *disposable = [[AdControllerWrapperHelper
          transformAdPresentationToTerminatingSignal:self.presentationStatus]
          subscribe:subscriber];

        [self.interstitialAd presentFromRootViewController:viewController];

        return disposable;

    }];

}

#pragma mark - <GADFullScreenContentDelegate> status relay

/// Tells the delegate that an impression has been recorded for the ad.
- (void)adDidRecordImpression:(nonnull id<GADFullScreenPresentingAd>)ad {
    // No-op.
}

/// Tells the delegate that the ad failed to present full screen content.
- (void)ad:(nonnull id<GADFullScreenPresentingAd>)ad
didFailToPresentFullScreenContentWithError:(nonnull NSError *)error {

    // Ad is consumed.
    // If the reference to GADInterstitialAd object is set to nil at any point,
    // before this callback, the object is deallocated and this callback is not called.
    self.interstitialAd = nil;

    [PsiFeedbackLogger errorWithType:AdMobInterstitialAdControllerWrapperLogType
                             message:@"AdMob didFailToPresentFullScreenContentWithError"
                              object:error];

    [self.adLoadStatus accept:@(AdLoadStatusNone)];
    [self.presentationStatus sendNext:@(AdPresentationErrorFailedToPlay)];

}

/// Tells the delegate that the ad presented full screen content.
- (void)adDidPresentFullScreenContent:(nonnull id<GADFullScreenPresentingAd>)ad {

    [self.adLoadStatus accept:@(AdLoadStatusNone)];

    // AdMob no longer provides an "willPresent/willAppear" callbacks.
    // For consistency WillAppear and DidAppear messages are sent.
    [self.presentationStatus sendNext:@(AdPresentationWillAppear)];
    [self.presentationStatus sendNext:@(AdPresentationDidAppear)];

}

/// Tells the delegate that the ad dismissed full screen content.
- (void)adDidDismissFullScreenContent:(nonnull id<GADFullScreenPresentingAd>)ad {

    // Ad is consumed.
    // If the reference to GADInterstitialAd object is set to nil at any point,
    // before this callback, the object is deallocated and this callback is not called.
    self.interstitialAd = nil;

    // AdMob no longer provides an "willDismiss/willDisappear" callbacks.
    // For consistency WillDisappear and DidDisappear messages are sent.
    [self.presentationStatus sendNext:@(AdPresentationWillDisappear)];
    [self.presentationStatus sendNext:@(AdPresentationDidDisappear)];

    [self.presentedAdDismissed sendNext:RACUnit.defaultUnit];

    [PsiFeedbackLogger infoWithType:AdMobInterstitialAdControllerWrapperLogType json:
     @{@"event": @"adDidDisappear", @"tag": self.tag}];

}

@end
