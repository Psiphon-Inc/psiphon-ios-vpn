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

#import "AdManager.h"
#import "GADMobileAds.h"
#import "VPNManager.h"

@interface AdManager ()

@property (nonatomic, retain) MPInterstitialAdController *untunneledInterstitial;

@end

@implementation AdManager {
    VPNManager *vpnManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.adIsShowing = FALSE;
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
    } else {
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

// TODO: deinit when in tunnel.

- (void)initializeAds {
    // TODO: decide if to init or deinit, based on VPN disconnected state.

    NSLog(@"initializeAds");
    if ([self shouldShowUntunneledAds]) {
        // Init code.
        [GADMobileAds configureWithApplicationID:@"ca-app-pub-1072041961750291~2085686375"];
        [self loadUntunneledInterstitial];
    } else {
        // De-init code.
        [MPInterstitialAdController removeSharedInterstitialAdController:self.untunneledInterstitial];
        self.untunneledInterstitial = nil;

        [self postAdsLoadStateDidChangeNotification];
    }
}

- (bool)shouldShowUntunneledAds {
    return [vpnManager getVPNStatus] == VPNStatusDisconnected;
}

- (void)loadUntunneledInterstitial {
    NSLog(@"loadUntunneledInterstitial");
    self.untunneledInterstitial = [MPInterstitialAdController
      interstitialAdControllerForAdUnitId:@"4250ebf7b28043e08ddbe04d444d79e4"];
    self.untunneledInterstitial.delegate = self;
    [self.untunneledInterstitial loadAd];
}

- (void)showUntunneledInterstitial {
    NSLog(@"showUntunneledInterstitial");
    // Start the tunnel in parallel with showing ads.
    // VPN won't start until [vpnManager startVPN] message is sent.
    [vpnManager startTunnelWithCompletionHandler:^(NSError *error) {

        // Don't show ads if failed to start the network extension.
        if (!error) {
            if ([self adIsReady]) {
                self.adIsShowing = YES;
                [self.untunneledInterstitial showFromViewController:self];
            }
        }
    }];
}

- (BOOL)adIsReady {
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
    NSLog(@"Interstitial loaded");

    [self postAdsLoadStateDidChangeNotification];

}

- (void)interstitialDidAppear:(MPInterstitialAdController *)interstitial {
    self.adIsShowing = TRUE;
}

- (void)interstitialDidFailToLoadAd:(MPInterstitialAdController *)interstitial {
    NSLog(@"Interstitial failed to load");
    // Don't retry.
    [self postAdsLoadStateDidChangeNotification];
}

- (void)interstitialDidExpire:(MPInterstitialAdController *)interstitial {
    NSLog(@"Interstitial expired");

    [self postAdsLoadStateDidChangeNotification];

    [interstitial loadAd];
}

- (void)interstitialDidDisappear:(MPInterstitialAdController *)interstitial {
    NSLog(@"Interstitial dismissed");

    [self postAdsLoadStateDidChangeNotification];

    self.adIsShowing = NO;

    // Post message to the extension to start the VPN
    // when the tunnel is established.
    // NOTE: if the tunnel is not connected yet, this is NO-OP.
    [vpnManager startVPN];
}

@end
