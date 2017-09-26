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
#import "IAPHelper.h"

@import GoogleMobileAds;

@interface AdManager ()

@property (nonatomic, retain) MPInterstitialAdController *untunneledInterstitial;

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

        [[NSNotificationCenter defaultCenter]
          addObserver:self selector:@selector(vpnStatusDidChange) name:@kVPNStatusChangeNotificationName object:vpnManager];
        //TODO: stop listening on dealloc.
    }
    return self;
}

- (void)vpnStatusDidChange {
    if ([vpnManager getVPNStatus] == VPNStatusDisconnected) {
        // The VPN is stopped. Initialize ads after a delay:
        //    - to ensure regular untunneled networking is ready
        //    - because it's likely the user will be leaving the app, so we don't want to request
        //      another ad right away
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self initializeAds];
        });
    } else if ([vpnManager getVPNStatus] == VPNStatusConnected) {
        [self initializeAds];
    }
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
        if (!self.untunneledInterstitial) {
           LOG_DEBUG(@"Initializing");
            // Init code.
            [GADMobileAds configureWithApplicationID:@"ca-app-pub-1072041961750291~2085686375"];
            [self loadUntunneledInterstitial];
        }
    } else if (!self.untunneledInterstitialIsShowing) {
       LOG_DEBUG(@"Deinitializing");
        // De-init code.
        [MPInterstitialAdController removeSharedInterstitialAdController:self.untunneledInterstitial];
        self.untunneledInterstitial = nil;
        self.untunneledInterstitialHasShown = FALSE;

        [self postAdsLoadStateDidChangeNotification];
    }
}

- (BOOL)shouldShowUntunneledAds {
    // Check if user has an active subscription first
    BOOL hasActiveSubscription = [[IAPHelper sharedInstance] hasActiveSubscriptionForDate:[NSDate date]];

    NetworkStatus networkStatus = [[Reachability reachabilityForInternetConnection] currentReachabilityStatus];
    VPNStatus vpnStatus = [vpnManager getVPNStatus];
    return networkStatus != NotReachable && (vpnStatus == VPNStatusInvalid || vpnStatus == VPNStatusDisconnected) && !hasActiveSubscription;
}

- (void)loadUntunneledInterstitial {
   LOG_DEBUG();
    self.untunneledInterstitial = [MPInterstitialAdController
      interstitialAdControllerForAdUnitId:@"4250ebf7b28043e08ddbe04d444d79e4"];
    self.untunneledInterstitial.delegate = self;
    [self.untunneledInterstitial loadAd];
}

- (void)showUntunneledInterstitial {
   LOG_DEBUG();
    if ([self untunneledInterstitialIsReady]) {
        [self.untunneledInterstitial showFromViewController:[[AppDelegate sharedAppDelegate] getMainViewController]];
    } else {
        // Start the tunnel
        [vpnManager startTunnelWithCompletionHandler:^(NSError *error) {}];
    }
}

- (BOOL)untunneledInterstitialIsReady {
    if (self.untunneledInterstitial) {
        return self.untunneledInterstitial.ready;
    }
    return FALSE;
}

// Posts kAdsDidLoad notification.
// Listeners of this message can call adIsReady to get the latest state.
- (void)postAdsLoadStateDidChangeNotification {
    [[NSNotificationCenter defaultCenter]
      postNotificationName:@kAdsDidLoad object:self];
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
    [self postAdsLoadStateDidChangeNotification];
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
    [vpnManager startTunnelWithCompletionHandler:^(NSError *error) {}];
}

@end
