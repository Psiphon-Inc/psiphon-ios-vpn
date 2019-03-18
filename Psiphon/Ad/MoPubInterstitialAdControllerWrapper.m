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

#import <ReactiveObjC/NSObject+RACPropertySubscribing.h>
#import <ReactiveObjC/RACDisposable.h>
#import <ReactiveObjC/RACSignal+Operations.h>
#import "MoPubInterstitialAdControllerWrapper.h"
#import "RACReplaySubject.h"
#import "NSError+Convenience.h"
#import "RACUnit.h"
#import "Logging.h"
#import "Asserts.h"
#import "RACTuple.h"
#import "RelaySubject.h"


PsiFeedbackLogType const MoPubInterstitialAdControllerWrapperLogType = @"MoPubInterstitialAdControllerWrapper";

@interface MoPubInterstitialAdControllerWrapper () <MPInterstitialAdControllerDelegate>

@property (nonatomic, readwrite, nonnull) BehaviorRelay<NSNumber *> *adLoadStatus;

/** presentedAdDismissed is hot infinite signal - emits RACUnit whenever an ad is presented. */
@property (nonatomic, readwrite, nonnull) RACSubject<RACUnit *> *presentedAdDismissed;

/** presentationStatus is hot infinite signal - emits items of type @(AdPresentation). */
@property (nonatomic, readwrite, nonnull) RACSubject<NSNumber *> *presentationStatus;

// Private properties
@property (nonatomic, readwrite, nullable) MPInterstitialAdController *interstitial;

/** loadStatus is hot non-completing relay subject - emits the wrapper tag when the ad has been loaded. */
@property (nonatomic, readwrite, nonnull) RelaySubject<RACTwoTuple<AdControllerTag, NSError *> *> *loadStatusRelay;

@property (nonatomic, readonly) NSString *adUnitID;

@end

@implementation MoPubInterstitialAdControllerWrapper

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

- (void)dealloc {
    [MPInterstitialAdController removeSharedInterstitialAdController:self.interstitial];
}

- (RACSignal<RACTwoTuple<AdControllerTag, NSError *> *> *)loadAd {

    MoPubInterstitialAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        // Subscribe to load status before loading an ad to prevent race-condition with "adDidLoad" delegate callback.
        RACDisposable *disposable = [weakSelf.loadStatusRelay subscribe:subscriber];

        if (!weakSelf.interstitial) {
            // From MoPub Docs: Subsequent calls for the same ad unit ID will return that object, unless you have disposed
            // of the object using `removeSharedInterstitialAdController:`.
            weakSelf.interstitial = [MPInterstitialAdController interstitialAdControllerForAdUnitId:weakSelf.adUnitID];

            // Sets the new delegate object as the interstitials delegate.

            if (!weakSelf.interstitial.delegate) {
                weakSelf.interstitial.delegate = weakSelf;
            }
        }

        // If the interstitial has already been loaded, `interstitialDidLoadAd:` delegate method will be called.
        [weakSelf.interstitial loadAd];

        [self.adLoadStatus accept:@(AdLoadStatusInProgress)];

        return disposable;
    }];
}

- (RACSignal<RACTwoTuple<AdControllerTag, NSError *> *> *)unloadAd {

    MoPubInterstitialAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        [MPInterstitialAdController removeSharedInterstitialAdController:weakSelf.interstitial];

        [weakSelf.adLoadStatus accept:@(AdLoadStatusNone)];

        [subscriber sendNext:[RACTwoTuple pack:weakSelf.tag :nil]];
        [subscriber sendCompleted];

        return nil;
    }];
}

- (RACSignal<NSNumber *> *)presentAdFromViewController:(UIViewController *)viewController {

    MoPubInterstitialAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        if (!weakSelf.interstitial.ready) {
            [subscriber sendNext:@(AdPresentationErrorNoAdsLoaded)];
            [subscriber sendCompleted];
            return nil;
        }

        // Subscribe to presentationStatus before presenting the ad.
        RACDisposable *disposable = [[AdControllerWrapperHelper
          transformAdPresentationToTerminatingSignal:weakSelf.presentationStatus]
          subscribe:subscriber];

        [weakSelf.interstitial showFromViewController:viewController];

        return disposable;
    }];
}

#pragma mark - <MPInterstitialAdControllerDelegate> status relay

- (void)interstitialDidLoadAd:(MPInterstitialAdController *)interstitial {
    [self.adLoadStatus accept:@(AdLoadStatusDone)];
    [self.loadStatusRelay accept:[RACTwoTuple pack:self.tag :nil]];
}

- (void)interstitialDidFailToLoadAd:(MPInterstitialAdController *)interstitial withError:(NSError *)error {

    [self.adLoadStatus accept:@(AdLoadStatusError)];

    NSError *e = [NSError errorWithDomain:AdControllerWrapperErrorDomain
                                     code:AdControllerWrapperErrorAdFailedToLoad
                      withUnderlyingError:error];

    [self.loadStatusRelay accept:[RACTwoTuple pack:self.tag :e]];
}

- (void)interstitialDidExpire:(MPInterstitialAdController *)interstitial {
    [self.adLoadStatus accept:@(AdLoadStatusNone)];

    NSError *e = [NSError errorWithDomain:AdControllerWrapperErrorDomain
                                     code:AdControllerWrapperErrorAdExpired];

    [self.loadStatusRelay accept:[RACTwoTuple pack:self.tag :e]];
}

- (void)interstitialWillAppear:(MPInterstitialAdController *)interstitial {
    [self.adLoadStatus accept:@(AdLoadStatusNone)];
    [self.presentationStatus sendNext:@(AdPresentationWillAppear)];
}

- (void)interstitialDidAppear:(MPInterstitialAdController *)interstitial {
    [self.presentationStatus sendNext:@(AdPresentationDidAppear)];
}

- (void)interstitialWillDisappear:(MPInterstitialAdController *)interstitial {
    [self.presentationStatus sendNext:@(AdPresentationWillDisappear)];
}

- (void)interstitialDidDisappear:(MPInterstitialAdController *)interstitial {
    [self.presentationStatus sendNext:@(AdPresentationDidDisappear)];
    [self.presentedAdDismissed sendNext:RACUnit.defaultUnit];

    [PsiFeedbackLogger infoWithType:MoPubInterstitialAdControllerWrapperLogType json:
      @{@"event": @"adDidDisappear", @"tag": self.tag}];
}

//- (void)interstitialDidReceiveTapEvent:(MPInterstitialAdController *)interstitial {
//}

@end
