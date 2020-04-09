#import "HYPRAdMobRewardedAdapter.h"
#import "HyprMXAdNetworkExtras.h"
#import "HYPRInitializationManager.h"
#import "HYPRAdMobUtils.h"

@interface HYPRAdMobRewardedAdapter () <HyprMXPlacementDelegate>
@property(nonatomic, strong, nullable) GADMediationRewardedLoadCompletionHandler completionHandler;
@property(nonatomic, weak, nullable) id <GADMediationRewardedAdEventDelegate> delegate;
@property(nonatomic, strong, nullable) NSString *placementName;
@end

@implementation HYPRAdMobRewardedAdapter

- (HyprMXPlacement *)placement {
    HyprMXPlacement *p = [HyprMX getPlacement:self.placementName];
    p.placementDelegate = self;

    if (![HYPRAdMobUtils isCompatibleType:REWARDED forPlacement:p]) {
        // Return invalid placement
        return [HyprMXPlacement new];
    }

    return p;
}

/**
 * The extras class that is used to specify additional parameters for a request to this ad network.
 */
+ (Class <GADAdNetworkExtras>)networkExtrasClass {
    return [HyprMXAdNetworkExtras class];
}

/**
 * Defines the SDK Version that we are tied to
 *
 * @return The version of the SDK we are tied to
 */
+ (GADVersionNumber)adSDKVersion {
    NSArray *versionComponents = [kHyprMarketplace_SDKVersion componentsSeparatedByString:@"."];
    GADVersionNumber version = {0};
    if (versionComponents.count == 3) {
        version.majorVersion = [versionComponents[0] integerValue];
        version.minorVersion = [versionComponents[1] integerValue];
        version.patchVersion = [versionComponents[2] integerValue];
    }
    return version;
}

/**
 * The version of the adapter.
 * Adapters are tied to SDKs and have a build number of their own.
 * In terms of reporting, we report only build number of the adapter
 *
 * @return The version of the adapter
 */
+ (GADVersionNumber)version {
    GADVersionNumber version = {0};
    version.patchVersion = kHyprMarketplace_BuildNumber;

    return version;
}

/**
 * NOTE: According the AdMob documentation this should be called to setup the SDK.  This does not appear to
 *       be the case for custom events.
 *
 * Tells the adapter to set up its underlying ad network SDK and perform any necessary prefetching
 * or configuration work. The adapter must call completionHandler once the adapter can service ad
 * requests, or if it encounters an error while setting up.
 */
+ (void)setUpWithConfiguration:(GADMediationServerConfiguration *)configuration
             completionHandler:(GADMediationAdapterSetUpCompletionBlock)completionHandler {

    NSLog(@"[HYPRAdMobRewardedAdapter] Unexpected call to setUpWithConfiguration");
    completionHandler(nil);
}

/**
  * Asks the adapter to load a rewarded ad with the provided ad configuration. The adapter must
  * call back completionHandler with the loaded ad, or it may call back with an error. This method
  * is called on the main thread, and completionHandler must be called back on the main thread.
  */
- (void)loadRewardedAdForAdConfiguration:(nonnull GADMediationRewardedAdConfiguration *)adConfiguration
                       completionHandler:(nonnull GADMediationRewardedLoadCompletionHandler)completionHandler {

    HyprMXAdNetworkExtras *extras = adConfiguration.extras;
    [HYPRInitializationManager manageUserIdWithUserID:extras.userId];

    NSDictionary *parameters = [HYPRAdMobUtils decodeServerParameter:adConfiguration.credentials.settings[kServerParameterKey]];

    self.placementName = parameters[kHyprServerParamPlacement];
    self.completionHandler = completionHandler;

    if (!self.placementName) {
        NSLog(@"[HYPRAdMobRewardedAdapter] loadRewardedAdForAdConfiguration requested with no placement name");
        [self failedToSetupRewardedAdapter];
        return;
    }

    NSLog(@"[HYPRAdMobRewardedAdapter] loadRewardedAdForAdConfiguration for placement %@", self.placementName);

    __weak HYPRAdMobRewardedAdapter *weakSelf = self;

    [[HYPRInitializationManager sharedInstance]
            initializeSDKWithDistributorId:parameters[kHyprServerParamDistID]
                             consentStatus:extras.consentStatus
                         completionHandler:^(BOOL didCompleteSuccessfully) {
                             if (didCompleteSuccessfully) {
                                 [weakSelf loadAd];
                             } else {
                                 NSLog(@"[HYPRAdMobRewardedAdapter] HyprMX failed to initialize");
                                 [weakSelf failedToSetupRewardedAdapter];
                             }
                         }];
}

- (void)loadAd {
    NSLog(@"[HYPRAdMobRewardedAdapter] Loading ad for placement %@", self.placementName);
    [[self placement] loadAd];
}

- (void)presentFromViewController:(nonnull UIViewController *)viewController {
    if ([[self placement] isAdAvailable]) {
        // The reward based video ad is available, present the ad.
        [[self placement] showAd];
    } else {
        NSError *error =
                [NSError errorWithDomain:@"GADMediationAdapterSampleAdNetwork"
                                    code:0
                                userInfo:@{NSLocalizedDescriptionKey: @"Unable to display ad."}];
        [self.delegate didFailToPresentWithError:error];
    }
}

- (void)adWillStartForPlacement:(HyprMXPlacement *)placement {
    [self.delegate willPresentFullScreenView];
    [self.delegate reportImpression];
    [self.delegate didStartVideo];
}

- (void)adDidCloseForPlacement:(HyprMXPlacement *)placement didFinishAd:(BOOL)finished {
    [self.delegate didEndVideo];
    [self.delegate willDismissFullScreenView];
    [self.delegate didDismissFullScreenView];
}

- (void)adDisplayErrorForPlacement:(HyprMXPlacement *)placement error:(HyprMXError)hyprMXError {
    NSString *message = @"Unknown";
    switch (hyprMXError) {
        case DISPLAY_ERROR:
            message = @"Error displaying Ad.";
            break;
        case NO_FILL:
            message = @"No Fill.";
            break;
        case PLACEMENT_DOES_NOT_EXIST:
            message = [NSString stringWithFormat:@"No such placement: %@", placement];
            break;
    }
    NSLog(@"[HyprMX] Error displaying %@ ad: %@", placement.placementName, message);
    NSError *error = [NSError errorWithDomain:kGADErrorDomain
                                         code:kGADErrorMediationAdapterError
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
    [self.delegate didFailToPresentWithError:error];
}

- (void)adAvailableForPlacement:(HyprMXPlacement *)placement {
    self.delegate = self.completionHandler(self, nil);
    self.completionHandler = nil;
}

- (void)adDidRewardForPlacement:(HyprMXPlacement *)placement rewardName:(NSString *)rewardName rewardValue:(NSInteger)rewardValue {
    GADAdReward *reward = [[GADAdReward alloc] initWithRewardType:rewardName
                                                     rewardAmount:[NSDecimalNumber numberWithInteger:rewardValue]];
    [self.delegate didRewardUserWithReward:reward];
}

- (void)adExpiredForPlacement:(HyprMXPlacement *)placement {
    // No AdMob support
    NSLog(@"[HYPRAdMobRewardedAdapter] The Ad for %@ has expired", self.placementName);
}


- (void)adNotAvailableForPlacement:(HyprMXPlacement *)placement {
    NSError *error = [NSError errorWithDomain:kGADErrorDomain
                                         code:kGADErrorNoFill
                                     userInfo:@{NSLocalizedDescriptionKey:
                                             @"No Ads Available"}];

    self.completionHandler(nil, error);
    self.completionHandler = nil;
}

- (void)failedToSetupRewardedAdapter {
    NSError *error = [NSError errorWithDomain:kGADErrorDomain
                                         code:kGADErrorMediationAdapterError
                                     userInfo:@{NSLocalizedDescriptionKey:
                                             @"Rewarded Adapter not initialized"}];
    self.completionHandler(nil, error);
    self.completionHandler = nil;
}
@end
