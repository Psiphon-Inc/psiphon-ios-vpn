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
#import "InterstitialAdControllerWrapper.h"
#import "RACReplaySubject.h"
#import "NSError+Convenience.h"
#import "RACUnit.h"
#import "Logging.h"


@interface InterstitialAdControllerWrapper () <MPInterstitialAdControllerDelegate>

@property (nonatomic, readwrite, assign) BOOL ready;

/** adPresented is hot infinite signal - emits RACUnit whenever an ad is presented. */
@property (nonatomic, readwrite, nonnull) RACSubject<RACUnit *> *adPresented;

/** presentationStatus is hot infinite signal - emits items of type @(AdPresentation). */
@property (nonatomic, readwrite, nonnull) RACSubject<NSNumber *> *presentationStatus;

// Private properties
@property (nonatomic, readwrite, nullable) MPInterstitialAdController *interstitial;

/** loadStatus is hot non-completing signal - emits the wrapper tag when the ad has been loaded. */
@property (nonatomic, readwrite, nonnull) RACSubject<NSString *> *loadStatus;

@property (nonatomic, readonly) NSString *adUnitID;

@end

@implementation InterstitialAdControllerWrapper

@synthesize tag = _tag;

- (instancetype)initWithAdUnitID:(NSString *)adUnitID withTag:(AdControllerTag)tag{
    _tag = tag;
    _loadStatus = [RACSubject subject];
    _adUnitID = adUnitID;
    _ready = FALSE;
    _adPresented = [RACSubject subject];
    _presentationStatus = [RACSubject subject];
    return self;
}

- (void)dealloc {
    [MPInterstitialAdController removeSharedInterstitialAdController:self.interstitial];
}

- (RACSignal<NSString *> *)loadAd {

    InterstitialAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        RACDisposable *disposable = [weakSelf.loadStatus subscribe:subscriber];

        if (!weakSelf.interstitial) {
            // From MoPub Docs: Subsequent calls for the same ad unit ID will return that object, unless you have disposed
            // of the object using `removeSharedInterstitialAdController:`.
            weakSelf.interstitial = [MPInterstitialAdController interstitialAdControllerForAdUnitId:weakSelf.adUnitID];

            // Sets the new delegate object as the interstitials delegate.
            weakSelf.interstitial.delegate = weakSelf;
        }

        // If the interstitial has already been loaded, `interstitialDidLoadAd:` delegate method will be called.
        [weakSelf.interstitial loadAd];
        
        return disposable;
    }];
}

- (RACSignal<NSString *> *)unloadAd {

    InterstitialAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        [MPInterstitialAdController removeSharedInterstitialAdController:weakSelf.interstitial];
        weakSelf.interstitial = nil;

        [subscriber sendNext:weakSelf.tag];
        [subscriber sendCompleted];

        return nil;
    }];
}

- (RACSignal<NSNumber *> *)presentAdFromViewController:(UIViewController *)viewController {

    InterstitialAdControllerWrapper *__weak weakSelf = self;

    return [RACSignal createSignal:^RACDisposable *(id <RACSubscriber> subscriber) {

        if (!weakSelf.interstitial.ready) {
            [subscriber sendNext:@(AdPresentationErrorNoAdsLoaded)];
            [subscriber sendCompleted];
            return nil;
        }

        RACDisposable *disposable = [weakSelf.presentationStatus subscribe:subscriber];
        [weakSelf.interstitial showFromViewController:viewController];

        return disposable;
    }];
}

#pragma mark - <MPInterstitialAdControllerDelegate> status relay

- (void)interstitialDidLoadAd:(MPInterstitialAdController *)interstitial {
    if (!self.ready) {
        self.ready = TRUE;
    }
    [self.loadStatus sendNext:self.tag];
}

- (void)interstitialDidFailToLoadAd:(MPInterstitialAdController *)interstitial withError:(NSError *)error {

    if (self.ready) {
        self.ready = FALSE;
    }

    [self.loadStatus sendError:[NSError errorWithDomain:AdControllerWrapperErrorDomain
                                                   code:AdControllerWrapperErrorAdFailedToLoad
                                    withUnderlyingError:error]];
}

- (void)interstitialDidExpire:(MPInterstitialAdController *)interstitial {
    if (self.ready) {
        self.ready = FALSE;
    }

    [self.loadStatus sendError:[NSError errorWithDomain:AdControllerWrapperErrorDomain
                                                   code:AdControllerWrapperErrorAdExpired]];
}

- (void)interstitialWillAppear:(MPInterstitialAdController *)interstitial {
    [self.presentationStatus sendNext:@(AdPresentationWillAppear)];
}

- (void)interstitialDidAppear:(MPInterstitialAdController *)interstitial {
    [self.presentationStatus sendNext:@(AdPresentationDidAppear)];
}

- (void)interstitialWillDisappear:(MPInterstitialAdController *)interstitial {
    [self.presentationStatus sendNext:@(AdPresentationWillDisappear)];
}

- (void)interstitialDidDisappear:(MPInterstitialAdController *)interstitial {
    if (self.ready) {
        self.ready = FALSE;
    }
    [self.presentationStatus sendNext:@(AdPresentationDidDisappear)];
    [self.adPresented sendNext:RACUnit.defaultUnit];
}

//- (void)interstitialDidReceiveTapEvent:(MPInterstitialAdController *)interstitial {
//}

@end
