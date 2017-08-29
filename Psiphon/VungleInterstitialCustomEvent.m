//
//  VungleInterstitialCustomEvent.m
//  MoPubSDK
//
//  Copyright (c) 2013 MoPub. All rights reserved.
//

#import <VungleSDK/VungleSDK.h>
#import "VungleInterstitialCustomEvent.h"
#import "MPInstanceProvider.h"
#import "MPLogging.h"
#import "MPVungleRouter.h"

// If you need to play ads with vungle options, you may modify playVungleAdFromRootViewController and create an options dictionary and call the playAd:withOptions: method on the vungle SDK.


static NSString *const kVunglePlacementIdKey = @"pid";


@interface VungleInterstitialCustomEvent () <MPVungleRouterDelegate>

@property (nonatomic, assign) BOOL handledAdAvailable;
@property (nonatomic, copy) NSString *placementId;

@end

@implementation VungleInterstitialCustomEvent


#pragma mark - MPInterstitialCustomEvent Subclass Methods

- (void)requestInterstitialWithCustomEventInfo:(NSDictionary *)info
{
    self.placementId = [info objectForKey:kVunglePlacementIdKey];

    self.handledAdAvailable = NO;
    [[MPVungleRouter sharedRouter] requestInterstitialAdWithCustomEventInfo:info delegate:self];
}

- (void)showInterstitialFromRootViewController:(UIViewController *)rootViewController
{
    if ([[MPVungleRouter sharedRouter] isAdAvailableForPlacementId:self.placementId]) {
        [[MPVungleRouter sharedRouter] presentInterstitialAdFromViewController:rootViewController forPlacementId:self.placementId];
    } else {
        MPLogInfo(@"Failed to show Vungle video interstitial: Vungle now claims that there is no available video ad.");
        [self.delegate interstitialCustomEvent:self didFailToLoadAdWithError:nil];
    }
}

- (void)invalidate
{
    [[MPVungleRouter sharedRouter] clearDelegateForPlacementId:self.placementId];
}

- (void)handleVungleAdViewWillClose
{
    MPLogInfo(@"Vungle video interstitial will disappear");

    [self.delegate interstitialCustomEventWillDisappear:self];
    [self.delegate interstitialCustomEventDidDisappear:self];
}

#pragma mark - MPVungleRouterDelegate

- (void)vungleAdDidLoad
{
    if (!self.handledAdAvailable) {
        self.handledAdAvailable = YES;
        [self.delegate interstitialCustomEvent:self didLoadAd:nil];
    }
}

- (void)vungleAdWillAppear
{
    MPLogInfo(@"Vungle video interstitial will appear");

    [self.delegate interstitialCustomEventWillAppear:self];
    [self.delegate interstitialCustomEventDidAppear:self];
}

- (void)vungleAdWillDisappear
{
    [self handleVungleAdViewWillClose];
}

- (void)vungleAdWasTapped
{
    [self.delegate interstitialCustomEventDidReceiveTapEvent:self];
}

- (void)vungleAdDidFailToLoad:(NSError *)error
{
    [self.delegate interstitialCustomEvent:self didFailToLoadAdWithError:error];
}

- (void)vungleAdDidFailToPlay:(NSError *)error
{
    [self.delegate interstitialCustomEvent:self didFailToLoadAdWithError:error];
}

@end
