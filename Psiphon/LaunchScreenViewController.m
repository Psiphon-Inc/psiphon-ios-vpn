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

@interface LaunchScreenViewController ()

@property (strong, nonatomic) AVPlayer *loadingVideo;
@property (nonatomic) AVPlayerItem *videoFile;

@end

static const NSString *ItemStatusContext;

@implementation LaunchScreenViewController {
    // videoPlayer
    AVPlayerLayer* playerLayer;

    // Loading Text
    UILabel *loadingLabel;
}

- (id)init {
    self = [super init];
    
    NSString *tracksKey = @"tracks";
    
    NSURL *fileURL = [[NSBundle mainBundle] URLForResource:@"launch" withExtension:@"m4v"];
    
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:nil];
    
    [asset loadValuesAsynchronouslyForKeys:@[tracksKey] completionHandler:^{
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *error;
            AVKeyValueStatus status = [asset statusOfValueForKey:tracksKey error:&error];
             if (status == AVKeyValueStatusLoaded) {
                 self.videoFile = [AVPlayerItem playerItemWithAsset:asset];
                 // ensure that this is done before the playerItem is associated with the player
                 [self.videoFile addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:&ItemStatusContext];
                 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.videoFile];
                 self.loadingVideo = [AVPlayer playerWithPlayerItem:self.videoFile];
                 
                 playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.loadingVideo];
                 if (self.view.bounds.size.width > self.view.bounds.size.height) {
                     // Landscape
                     playerLayer.frame = CGRectMake((self.view.bounds.size.width - self.view.bounds.size.width / 1.5) / 2, 30, self.view.bounds.size.width / 1.5, self.view.bounds.size.height / 1.5);
                 } else {
                     playerLayer.frame = CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height);
                 }
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

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {

    if (size.width > size.height) {
        // Landscape
        playerLayer.frame = CGRectMake(( size.width - size.width / 1.5 ) / 2, 30, size.width / 1.5, size.height / 1.5);
    } else {
        playerLayer.frame = CGRectMake(0, 0, size.width, size.height);
    }

    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    }];

    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // TODO: Add something to handle the syncUI when screen rotate
    [self.view setBackgroundColor:[UIColor blackColor]];
    [self addLoadingLabel];
    [self addProgressView];
    [self setNeedsStatusBarAppearanceUpdate];
    [self syncUI];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.loadingVideo play];
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    [self.loadingVideo seekToTime:kCMTimeZero];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)shouldAutorotate {
    if ([[UIDevice currentDevice].model hasPrefix:@"iPhone"]) {
        return NO;
    }
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if ([[UIDevice currentDevice].model hasPrefix:@"iPhone"]) {
        return UIInterfaceOrientationMaskPortrait + UIInterfaceOrientationMaskPortraitUpsideDown;
    }
    return YES;
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

- (void)addLoadingLabel {
    loadingLabel = [[UILabel alloc] init];
    loadingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    loadingLabel.adjustsFontSizeToFitWidth = YES;
    loadingLabel.text = @"Loading...";
    loadingLabel.textAlignment = NSTextAlignmentCenter;
    loadingLabel.textColor = [UIColor whiteColor];
    [self.view addSubview:loadingLabel];
    
    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:loadingLabel
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:-30.0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:loadingLabel
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:-30.0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:loadingLabel
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.0
                                                           constant:30]];
}

- (void)addProgressView {
    self.progressView = [[UIProgressView alloc] init];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.progressView];
    
    // Setup autolayout
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.progressView
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                             toItem:loadingLabel
                                                          attribute:NSLayoutAttributeTop
                                                         multiplier:1.0
                                                           constant:-15.0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.progressView
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.0
                                                           constant:15.0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.progressView
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:-15.0]];
}

@end
