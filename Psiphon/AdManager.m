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

#import <PsiphonTunnel/Reachability.h>
#import "AdManager.h"
#import "VPNManager.h"
#import "AppDelegate.h"
#import "Logging.h"
#import "IAPStoreHelper.h"
#import "RACCompoundDisposable.h"
#import "RACSignal.h"
#import "RACSignal+Operations.h"
#import "RACReplaySubject.h"

@import GoogleMobileAds;

NSNotificationName const AdManagerAdsDidLoadNotification = @"AdManagerAdsDidLoadNotification";
NSString* const kUntunneledInterstitialAddUnitID = @"4250ebf7b28043e08ddbe04d444d79e4";

@interface AdManager ()

@property (nonatomic, retain) MPInterstitialAdController *untunneledInterstitial;

@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@end

@implementation AdManager {
    VPNManager *vpnManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.untunneledInterstitialIsShowing = FALSE;
        self.untunneledInterstitialHasShown = FALSE;
        vpnManager = [VPNManager sharedInstance];

        _compoundDisposable = [RACCompoundDisposable compoundDisposable];

        // Observe VPN status values.
        __block RACDisposable *disposable = [vpnManager.lastTunnelStatus
          subscribeNext:^(NSNumber *statusObject) {
              VPNStatus s = (VPNStatus) [statusObject integerValue];

              if (s == VPNStatusDisconnected) {
                  // The VPN is stopped. Initialize ads after a delay:
                  //    - to ensure regular untunneled networking is ready
                  //    - because it's likely the user will be leaving the app, so we don't want to request
                  //      another ad right away
                  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                      [self initializeAds];
                  });
              } else if (s == VPNStatusConnected) {
                  [self initializeAds];
              }
          } error:^(NSError *error) {
              [_compoundDisposable removeDisposable:disposable];
          } completed:^{
              [_compoundDisposable removeDisposable:disposable];
          }];

        [_compoundDisposable addDisposable:disposable];

    }
    return self;
}

- (void)dealloc {
    [self.compoundDisposable dispose];
}

#pragma mark - Public methods

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)initializeAds {
    LOG_DEBUG();
    if ([self shouldShowUntunneledAds]) {
        //  Consent presenter/ad loader helper block
        void(^showConsentDialogOrLoadAds)(void) = ^{
            // Try and load/show the consent dialog if needed, otherwise load ads
            if ([MoPub sharedInstance].shouldShowConsentDialog) {
                [[MoPub sharedInstance] loadConsentDialogWithCompletion:^(NSError *error){
                    if (error == nil) {
                        [[MoPub sharedInstance] showConsentDialogFromViewController:[[AppDelegate sharedAppDelegate] getAdsPresentingViewController] completion:nil];
                    } else {
                        LOG_DEBUG(@"MoPub failed to load consent dialog with error: %@", error);
                    }
                }];
            } else {
                if (!self.untunneledInterstitial) {
                    LOG_DEBUG(@"Loading ads");
                    // Init code.
                    [GADMobileAds configureWithApplicationID:@"ca-app-pub-1072041961750291~2085686375"];
                    [self loadUntunneledInterstitial];
                }
            }
        };

        // Initialize MoPub if needed, upon completion present consent dialog or load ads
        if(MPConsentManager.sharedManager.adUnitIdUsedForConsent == nil ) {
            MPMoPubConfiguration * sdkConfig = [[MPMoPubConfiguration alloc] initWithAdUnitIdForAppInitialization: kUntunneledInterstitialAddUnitID];
            sdkConfig.globalMediationSettings = @[];
            sdkConfig.mediatedNetworks = @[];
            sdkConfig.advancedBidders = nil;
            [[MoPub sharedInstance] initializeSdkWithConfiguration:sdkConfig completion:^{
                dispatch_async(dispatch_get_main_queue(), showConsentDialogOrLoadAds);
            }];
        } else {
            dispatch_async(dispatch_get_main_queue(), showConsentDialogOrLoadAds);
        }
    } else if (!self.untunneledInterstitialIsShowing) {
        [self deinitializeAds];
    }
}

- (void)deinitializeAds {
    LOG_DEBUG(@"Deinitializing");
    // De-init code.
    [MPInterstitialAdController removeSharedInterstitialAdController:self.untunneledInterstitial];
    self.untunneledInterstitial = nil;
    self.untunneledInterstitialHasShown = FALSE;
    
    [self postAdsLoadStateDidChangeNotification];
}

// TODO: This is a blocking function called on main thread.
- (BOOL)shouldShowUntunneledAds {
    // Check if user has an active subscription first
    BOOL hasActiveSubscription = [IAPStoreHelper hasActiveSubscriptionForNow];

    NetworkStatus networkStatus = [[Reachability reachabilityForInternetConnection] currentReachabilityStatus];
    VPNStatus s = (VPNStatus) [[vpnManager.lastTunnelStatus first] integerValue];
    return networkStatus != NotReachable && (s == VPNStatusInvalid || s == VPNStatusDisconnected) && !hasActiveSubscription;
}

- (void)loadUntunneledInterstitial {
   LOG_DEBUG();
    self.untunneledInterstitial = [MPInterstitialAdController
      interstitialAdControllerForAdUnitId:kUntunneledInterstitialAddUnitID];
    self.untunneledInterstitial.delegate = self;
    [self.untunneledInterstitial loadAd];
}

- (void)showUntunneledInterstitial {
   LOG_DEBUG();
    if ([self untunneledInterstitialIsReady]) {
        [self.untunneledInterstitial showFromViewController:[[AppDelegate sharedAppDelegate] getAdsPresentingViewController]];
    } else {
        // Start the tunnel
        [vpnManager startTunnel];
    }
}

- (BOOL)untunneledInterstitialIsReady {
    if (self.untunneledInterstitial) {
        return self.untunneledInterstitial.ready;
    }
    return FALSE;
}

// Posts AdManagerAdsDidLoadNotification notification.
// Listeners of this message can call adIsReady to get the latest state.
- (void)postAdsLoadStateDidChangeNotification {
    [[NSNotificationCenter defaultCenter]
      postNotificationName:AdManagerAdsDidLoadNotification object:self];
}

#pragma mark - Interestitial callbacks

- (void)interstitialDidLoadAd:(MPInterstitialAdController *)interstitial {
   LOG_DEBUG();

    [self postAdsLoadStateDidChangeNotification];
}

- (void)interstitialWillAppear:(MPInterstitialAdController *)interstitial {
   LOG_DEBUG();
    
    self.untunneledInterstitialIsShowing = TRUE;
    self.untunneledInterstitialHasShown = TRUE;
}

- (void)interstitialDidFailToLoadAd:(MPInterstitialAdController *)interstitial {
   LOG_DEBUG();
    
    // Don't retry.
    [self deinitializeAds];
}

- (void)interstitialDidExpire:(MPInterstitialAdController *)interstitial {
   LOG_DEBUG();

    [self postAdsLoadStateDidChangeNotification];

    [interstitial loadAd];
}

- (void)interstitialDidDisappear:(MPInterstitialAdController *)interstitial {
   LOG_DEBUG();

    self.untunneledInterstitialIsShowing = FALSE;
    
    [self postAdsLoadStateDidChangeNotification];

    // Start the tunnel
    [vpnManager startTunnel];
}

@end
