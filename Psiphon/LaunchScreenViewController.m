
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

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "LaunchScreenViewController.h"
#import "AppDelegate.h"
#import "ViewController.h"

@import NetworkExtension;
@import GoogleMobileAds;

@interface LaunchScreenViewController ()

@property (nonatomic) NEVPNManager *targetManager;

@property (strong, nonatomic) AVPlayer *loadingVideo;
@property (nonatomic) AVPlayerItem *viedoFile;

@end

static const NSString *ItemStatusContext;

@implementation LaunchScreenViewController {
    // Ads
    BOOL adsLoaded;
    
    // Loading Timer
    NSTimer *_loadingTimer;

    // Main View Controller
    ViewController *mainViewController;
}

- (id)init {
    self = [super init];
    
    NSString *tracksKey = @"tracks";
    
    NSURL *fileURL = [[NSBundle mainBundle] URLForResource:@"loading" withExtension:@"mov"];
    
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:nil];
    
    [asset loadValuesAsynchronouslyForKeys:@[tracksKey] completionHandler:^{
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *error;
            AVKeyValueStatus status = [asset statusOfValueForKey:tracksKey error:&error];
             if (status == AVKeyValueStatusLoaded) {
                 self.viedoFile = [AVPlayerItem playerItemWithAsset:asset];
                 // ensure that this is done before the playerItem is associated with the player
                 [self.viedoFile addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:&ItemStatusContext];
                 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.viedoFile];
                 self.loadingVideo = [AVPlayer playerWithPlayerItem:self.viedoFile];
                 
                 AVPlayerLayer* playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.loadingVideo];
                 playerLayer.frame = self.view.bounds;
                 playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
                 playerLayer.needsDisplayOnBoundsChange = YES;
                 NSLog(@"Loading Video");
                 [self.view.layer addSublayer:playerLayer];
                 self.view.layer.needsDisplayOnBoundsChange = YES;
             }
             else {
                 // You should deal with the error appropriately.
                 NSLog(@"The asset's tracks were not loaded:\n%@", [error localizedDescription]);
             }
        });
     }];
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // TODO: Add something to handle the syncUI when screen rotate
    [self.view setBackgroundColor:[UIColor whiteColor]];
    [self syncUI];
    mainViewController =  [[ViewController alloc] init];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.loadingVideo play];
    NSLog(@"Play Video");
    [self initializeAds];
    [self startLaunchingScreenTimer];
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    [self.loadingVideo seekToTime:kCMTimeZero];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if (context == &ItemStatusContext) {
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           [self syncUI];
                       });
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object
                           change:change context:context];
    return;
}

- (void)syncUI {
    if ((self.loadingVideo.currentItem != nil) &&
        ([self.loadingVideo.currentItem status] == AVPlayerItemStatusReadyToPlay)) {
            [self.loadingVideo play];
    }
}

- (void) switchViewControllerWhenExpire:(NSTimer*)timer {
    if (self.viedoFile != nil) {
        [self.viedoFile removeObserver:self forKeyPath:@"status"];
    }
    [[AppDelegate sharedAppDelegate] switchToMainViewController:_untunneledInterstitial:mainViewController];
}

- (void) startLaunchingScreenTimer {
    if (!_loadingTimer || ![_loadingTimer isValid]) {
        _loadingTimer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                           target:self
                                                         selector:@selector(switchViewControllerWhenExpire:)
                                                         userInfo:nil
                                                          repeats:NO];
    }
}

/*!
 @brief Returns true if NEVPNConnectionStatus is Connected, Connecting or Reasserting.
 */
- (BOOL) isVPNActive{
    NEVPNStatus status = self.targetManager.connection.status;
    return (status == NEVPNStatusConnecting
            || status == NEVPNStatusConnected
            || status == NEVPNStatusReasserting);
}

# pragma mark - Ads

- (void)initializeAds {
    NSLog(@"initializeAds");
    if (![self isVPNActive]) {
        [GADMobileAds configureWithApplicationID:@"ca-app-pub-1072041961750291~2085686375"];
        [self loadUntunneledInterstitial];
    }
}

- (void)loadUntunneledInterstitial {
    NSLog(@"loadUntunneledInterstitial");
    self.untunneledInterstitial = [MPInterstitialAdController
        interstitialAdControllerForAdUnitId:@"4250ebf7b28043e08ddbe04d444d79e4"];

    self.untunneledInterstitial.delegate = mainViewController;

    [self.untunneledInterstitial loadAd];
}

@end
