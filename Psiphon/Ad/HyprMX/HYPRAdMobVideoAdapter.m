//
//  HYPRAdMobVideoAdapter.m
//  HyprMX AdMobSDK Adapter

#import "HYPRAdMobVideoAdapter.h"
#import "HyprMXAdNetworkExtras.h"
@import HyprMX;

NSString * const kHyprMXServerLabelKey = @"HYPRAdMobVideoAdapter";
NSString * const kHyprMXUserIdKey = @"kHyprMXUserId";
NSString * const kHyprMXConsentStatusKey = @"kHyprMXConsentStatus";
NSString * const kHyprMarketplace_HYPRAdMobVideoAdapter_Version = @"5.1.1";
NSString * const kHyprMarketplaceAppConfigKeyUserId = @"hyprMarketplaceAppConfigKeyUserId";
NSString * const kHyprServerParamDistID = @"distributorID";
NSString * const kHyprServerParamPlacement = @"placementName";
// Constant defined as a workaround for GADCustomEventParametersServer not linking in AdMob's SDK above version 7.31.0
NSString * const kServerParameterKey = @"parameter";


typedef void (^HYPRInitCompletetionHandler)(BOOL didCompleteSuccessfully);

@interface HYPRInitializationManager : NSObject <HyprMXInitializationDelegate>

@property (nonatomic, strong) NSString *hyprUserId;
@property (nonatomic, strong) NSString *hyprDistributorId;
@property (nonatomic) HyprConsentStatus hyprConsentStatus;
@property (atomic, strong) NSMutableArray<HYPRInitCompletetionHandler> *completionCallbackBlocks;

+ (HYPRInitializationManager *)sharedInstance;
- (void)initializeSDKWithDistributorId:(NSString *)distributorId consentStatus:(HyprConsentStatus)consentStatus completionHandler:(HYPRInitCompletetionHandler)completionHandler;

@end


@implementation HYPRInitializationManager

+ (HYPRInitializationManager *)sharedInstance {
    static HYPRInitializationManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _completionCallbackBlocks = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)initializeSDKWithDistributorId:(NSString *)distributorId consentStatus:(HyprConsentStatus)consentStatus completionHandler:(HYPRInitCompletetionHandler)completionHandler {
    if (self.hyprDistributorId && ![self.hyprDistributorId isEqualToString:distributorId]) {
        NSLog(@"[HyprMX] WARNING: HYPRManager already initialized with another distributor ID");
        completionHandler(false);
        return;
    }
    NSString *savedUserID = [[NSUserDefaults standardUserDefaults] objectForKey:kHyprMarketplaceAppConfigKeyUserId];

    switch (HyprMX.initializationStatus) {
        case NOT_INITIALIZED:
        case INITIALIZATION_FAILED:
            NSLog(@"[HyprMX] Initializing SDK with Distributor Id: %@", distributorId);

            [self.completionCallbackBlocks addObject:completionHandler];

            [HyprMX initializeWithDistributorId:distributorId userId:savedUserID
                                  consentStatus:consentStatus
                         initializationDelegate:self];
            self.hyprUserId = savedUserID;
            self.hyprDistributorId = distributorId;
            self.hyprConsentStatus = consentStatus;
            break;
        case INITIALIZING:
            NSLog(@"[HyprMX] Initialization already in progress.  Waiting for init response");
            // Note.  What should we do here when the parameter changes during an init request?
            [self.completionCallbackBlocks addObject:completionHandler];
            break;
        case INITIALIZATION_COMPLETE:
            if (![self.hyprUserId isEqualToString:savedUserID]) {
                NSLog(@"[HyprMX] User ID has changed.  Re-initializing.");
                NSLog(@"[HyprMX] Initializing SDK with Distributor Id: %@", distributorId);

                [self.completionCallbackBlocks addObject:completionHandler];

                [HyprMX initializeWithDistributorId:distributorId userId:savedUserID
                                      consentStatus:consentStatus
                             initializationDelegate:self];
                self.hyprUserId = savedUserID;
                self.hyprDistributorId = distributorId;
                self.hyprConsentStatus = consentStatus;
                break;
            }

            if (self.hyprConsentStatus != consentStatus) {
                NSLog(@"[HyprMX] Consent status changed. ");
                [HyprMX setConsentStatus:consentStatus];
                self.hyprConsentStatus = consentStatus;
            }
            completionHandler(true);
            break;
    }
}

- (void)initializationDidComplete {
    NSLog(@"[HYPR] initializationDidComplete");
    for (HYPRInitCompletetionHandler callback in self.completionCallbackBlocks)
    {
        callback(true);
    }
    [self.completionCallbackBlocks removeAllObjects];
}

- (void)initializationFailed {
    NSLog(@"[HYPR] initializationFailed");
    for (HYPRInitCompletetionHandler callback in self.completionCallbackBlocks)
    {
        callback(false);
    }
    [self.completionCallbackBlocks removeAllObjects];
}

@end

@interface HYPRAdMobVideoAdapter() <HyprMXPlacementDelegate, HyprMXInitializationDelegate>
@property(nonatomic, weak) id<GADMRewardBasedVideoAdNetworkConnector> rewardConnector;
@property(readonly) HyprMXPlacement *rewardedPlacement;
@property(readonly) HyprMXPlacement *interstitialPlacement;
@property (strong, nonatomic) NSString *interstitialPlacementName;
@property (strong, nonatomic) NSString *rewardedPlacementName;

@end

@implementation HYPRAdMobVideoAdapter

- (HyprMXPlacement *)rewardedPlacement {
    HyprMXPlacement *p = [HyprMX getPlacement:self.rewardedPlacementName];
    p.placementDelegate = self;

    if ([self isIncompatibleType:REWARDED forPlacement:p]) {
        // Return invalid placement
        return [HyprMXPlacement new];
    }

    return p;
}

- (HyprMXPlacement *)interstitialPlacement {
    HyprMXPlacement *p = [HyprMX getPlacement:self.interstitialPlacementName];
    p.placementDelegate = self;

    if ([self isIncompatibleType:INTERSTITIAL forPlacement:p]) {
        // Return invalid placement
        return [HyprMXPlacement new];
    }

    return p;
}

- (BOOL)isIncompatibleType:(HyprMXPlacementType)type
              forPlacement:(HyprMXPlacement*)placement {

    if (placement.placementType != INVALID && placement.placementType != type) {
        NSString *correctType = type == INTERSTITIAL ? [HyprMXPlacement INTERSTITIAL] : [HyprMXPlacement REWARDED];
        NSString *incorrectType = type == INTERSTITIAL ? [HyprMXPlacement REWARDED] : [HyprMXPlacement INTERSTITIAL];
        NSLog(@"[HyprMX] HYPRAdMobVideoAdapter requested a placement of type %@ for an ad of type %@.", incorrectType, correctType);
        return YES;
    }

    return NO;
}

/*
 * Placement names are optional. Default used when nil or empty string.
 */

- (NSString*)interstitialPlacementName {
    if (_interstitialPlacementName.length == 0) {
        return HyprMXPlacement.INTERSTITIAL;
    }

    return _interstitialPlacementName;
}

- (NSString*)rewardedPlacementName {
    if (_rewardedPlacementName.length == 0) {
        return HyprMXPlacement.REWARDED;
    }

    return _rewardedPlacementName;
}

- (NSDictionary*)decodeServerParameter:(NSString*)serverParameter {

    if (!serverParameter
        || ![serverParameter isKindOfClass:NSString.class]
        || serverParameter.length == 0) {

        NSLog(@"[HyprMX] HYPRAdMobVideoAdapter could not initialize - serverParameter must be a non-empty string. Please check your AdMob Dashboard's AdUnit Settings");

        return nil;
    }

    NSError *error;
    NSDictionary *decodedJSON = [NSJSONSerialization JSONObjectWithData:[serverParameter dataUsingEncoding:NSUTF8StringEncoding]
                                                                options:0
                                                                  error:&error];
    if (error) {
        NSLog(@"[HyprMX] HYPRAdMobVideoAdapter could not parse JSON in server parameter");

        /*
         * We assume in this case the server parameter is just the distributor ID as a string
         */

        return @{kHyprServerParamDistID: serverParameter};
    }

    NSString *distributorID = decodedJSON[kHyprServerParamDistID];

    if (distributorID.length == 0) {
        NSLog(@"[HyprMX] HYPRAdMobVideoAdapter received invalid distributor ID in server parameter");
    }

    return decodedJSON;
}

#pragma mark - HyprMX GADCustomEventInterstitial Implementation -
@synthesize delegate;

- (void)requestInterstitialAdWithParameter:(NSString *)serverParameter
                                     label:(NSString *)serverLabel
                                   request:(GADCustomEventRequest *)request {

    NSDictionary *decodedServerParam = [self decodeServerParameter:serverParameter];
    NSString *distributorID = decodedServerParam[kHyprServerParamDistID];
    self.interstitialPlacementName = decodedServerParam[kHyprServerParamPlacement];

    NSLog(@"[HyprMX] Loading interstitial ad for %@", self.interstitialPlacementName);

    NSString *userIdFromExtras = nil;
    HyprConsentStatus status = CONSENT_STATUS_UNKNOWN;
    userIdFromExtras = request.additionalParameters[kHyprMXUserIdKey];
    [HYPRAdMobVideoAdapter manageUserIdWithUserID:userIdFromExtras];
    if (request.additionalParameters[kHyprMXConsentStatusKey]) {
        status = (HyprConsentStatus)[request.additionalParameters[kHyprMXConsentStatusKey] integerValue];
    }

    __weak HYPRAdMobVideoAdapter *weakSelf = self;

    [[HYPRInitializationManager sharedInstance] initializeSDKWithDistributorId:distributorID
                                                                               consentStatus:status
                                                                           completionHandler:^(BOOL didCompleteSuccessfully){

        if(didCompleteSuccessfully) {
            [weakSelf.interstitialPlacement loadAd];
        } else {
            [weakSelf failedToLoadInterstitialPlacement];
        }
    }];
}

- (void)presentFromRootViewController:(UIViewController *)rootViewController {
    if (self.interstitialPlacement.isAdAvailable) {
        [self.interstitialPlacement showAd];
    } else {
        NSLog(@"[HyprMX] No ad available");
        // dispatching asynchronously to follow the same pattern as the presentRewardBasedVideoAdWithRootViewController
        __weak HYPRAdMobVideoAdapter *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.delegate customEventInterstitialDidDismiss:weakSelf];
        });
    }
}


#pragma mark - HyprMX GADMRewardBasedVideoAdNetworkAdapter Implementation -

- (instancetype)initWithRewardBasedVideoAdNetworkConnector:(id<GADMRewardBasedVideoAdNetworkConnector>)connector {
    NSLog(@"[HYPR] initWithRewardBasedVideoAdNetworkConnector");
    if (!connector) {
        return nil;
    }
    if (self = [super init]) {
        NSString *serverParameter = connector.credentials[kServerParameterKey];
        if (serverParameter == nil || ![serverParameter isKindOfClass:[NSString class]] || [serverParameter length] == 0 ) {
            NSLog(@"[HyprMX] HYPRAdMobVideoAdapter could not initialize - distributorID must be a non-empty string. Please check your AdMob Dashboard's AdUnit Settings");
            return nil;
        }
        _rewardConnector = connector;
    }
    return self;
}

- (void)setUp {
    NSLog(@"[HYPR] setup");
    NSString *serverParam = self.rewardConnector.credentials[kServerParameterKey];
    NSDictionary *decodedServerParam = [self decodeServerParameter:serverParam];
    NSString *distributorID = decodedServerParam[kHyprServerParamDistID];

    NSLog(@"[HyprMX] Initializing Rewarded Adapter");

    HyprMXAdNetworkExtras *extras = _rewardConnector.networkExtras;
    [HYPRAdMobVideoAdapter manageUserIdWithUserID:extras.userId];

    __weak HYPRAdMobVideoAdapter *weakSelf = self;

    [[HYPRInitializationManager sharedInstance]
            initializeSDKWithDistributorId:distributorID
                             consentStatus:extras.consentStatus
                         completionHandler:^(BOOL didCompleteSuccessfully) {
                             if (didCompleteSuccessfully) {
                                 // Returning too quickly causes AdMob to doubly call requestRewardBasedVideoAd
                                 // This would happen if we were first initialized with an interstitial and then
                                 // with a rewarded.  dispatching asynchronously seems to alleviate this issue.
                                 NSLog(@"[HyprMX] Rewarded Adapter initialized successfully");
                                 dispatch_async(dispatch_get_main_queue(), ^{
                                     [weakSelf.rewardConnector adapterDidSetUpRewardBasedVideoAd:weakSelf];
                                 });
                             } else {
                                 [weakSelf failedToSetupRewardedAdapter];
                             }
                         }];
}

- (void)requestRewardBasedVideoAd {
    NSString *serverParam = self.rewardConnector.credentials[kServerParameterKey];
    NSDictionary *decodedServerParam = [self decodeServerParameter:serverParam];
    self.rewardedPlacementName = decodedServerParam[kHyprServerParamPlacement];
    NSString *distributorID = decodedServerParam[kHyprServerParamDistID];

    HyprMXAdNetworkExtras *extras = _rewardConnector.networkExtras;
    [HYPRAdMobVideoAdapter manageUserIdWithUserID:extras.userId];

    __weak HYPRAdMobVideoAdapter *weakSelf = self;

    [[HYPRInitializationManager sharedInstance]
            initializeSDKWithDistributorId:distributorID
                             consentStatus:extras.consentStatus
                         completionHandler:^(BOOL didCompleteSuccessfully) {
                             if (didCompleteSuccessfully) {
                                 NSLog(@"[HyprMX] Requesting inventory on %@", self.rewardedPlacement.placementName);
                                 [weakSelf.rewardedPlacement loadAd];
                             } else {
                                 [weakSelf failedToLoadRewardedPlacement];
                             }
                         }];
}

- (void)presentRewardBasedVideoAdWithRootViewController:(UIViewController *)viewController {
    if (self.rewardedPlacement.isAdAvailable) {
        [self.rewardedPlacement showAd];
    } else {
        NSLog(@"[HyprMX] No ad available");
        __weak HYPRAdMobVideoAdapter *weakSelf = self;
        // Returning too quickly causes AdMob to not process the adapterDidCloseRewardBasedVideoAd
        // And they think we are still showing
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.rewardConnector adapterDidCloseRewardBasedVideoAd:weakSelf];
        });
    }
}


#pragma mark - HyprMX GADMRewardBasedVideoAdNetworkAdapter / GADMAdNetworkAdapter Implementation -

+ (NSString *)adapterVersion {
    return kHyprMarketplace_HYPRAdMobVideoAdapter_Version;
}

+ (Class<GADAdNetworkExtras>)networkExtrasClass {
    return [HyprMXAdNetworkExtras class];
}

- (void)dealloc {
    _rewardConnector = nil;

}

// Tells the adapter to remove itself as a delegate or notification observer from the underlying ad
// network SDK.
- (void)stopBeingDelegate {}

#pragma mark - HyprMX Core -

+ (void)manageUserIdWithUserID:(NSString *)userID {
    NSString *finalId = nil;
    NSString *savedUserID = [[NSUserDefaults standardUserDefaults] objectForKey:kHyprMarketplaceAppConfigKeyUserId];
    if (userID.length < 1) {
        if (savedUserID.length < 1) {
            finalId = [[NSUUID UUID] UUIDString];
        } else {
            finalId = savedUserID;
        }
    } else {
        finalId = userID;
    }
    
    if (![finalId isEqualToString:savedUserID]) {
        [[NSUserDefaults standardUserDefaults] setObject:finalId
                                                  forKey:kHyprMarketplaceAppConfigKeyUserId];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)adWillStartForPlacement:(HyprMXPlacement *)placement {
    if ([placement isEqual:self.interstitialPlacement]) {
        [self.delegate customEventInterstitialWillPresent:self];
    } else {
        [self.rewardConnector adapterDidOpenRewardBasedVideoAd:self];
        [self.rewardConnector adapterDidStartPlayingRewardBasedVideoAd:self];
    }
}

- (void)adDidCloseForPlacement:(HyprMXPlacement *)placement didFinishAd:(BOOL)finished {
    if ([placement isEqual:self.interstitialPlacement]) {
        [self.delegate customEventInterstitialWillDismiss:self];
        [self.delegate customEventInterstitialDidDismiss:self];
    } else {
        [self.rewardConnector adapterDidCloseRewardBasedVideoAd:self];
    }
}

- (void)adDidRewardForPlacement:(HyprMXPlacement *)placement rewardName:(NSString *)rewardName rewardValue:(NSInteger)rewardValue {
    if ([placement isEqual:self.rewardedPlacement]) {
        [self.rewardConnector adapter:self
              didRewardUserWithReward:[[GADAdReward alloc] initWithRewardType:rewardName
                                                                 rewardAmount:[NSDecimalNumber decimalNumberWithDecimal:[NSNumber numberWithInteger:rewardValue].decimalValue]]];
    }
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
    if ([placement isEqual:self.interstitialPlacement]) {
        [self.delegate customEventInterstitialDidDismiss:self];
    } else {
        [self.rewardConnector adapterDidCloseRewardBasedVideoAd:self];
    }
}

- (void)adAvailableForPlacement:(HyprMXPlacement *)placement {
    NSLog(@"[HYPR] Ad available for %@", placement.placementName);
    if ([placement isEqual:self.interstitialPlacement]) {
        [self.delegate customEventInterstitialDidReceiveAd:self];
    } else {
        [self.rewardConnector adapterDidReceiveRewardBasedVideoAd:self];
    }
}

- (void)adNotAvailableForPlacement:(HyprMXPlacement *)placement {
    if ([placement isEqual:self.interstitialPlacement]) {
        [self failedToLoadInterstitialPlacement];
    } else {
        [self failedToLoadRewardedPlacement];
    }
}

- (void)failedToSetupRewardedAdapter {
    NSError *error = [NSError errorWithDomain:kGADErrorDomain
                                         code:kGADErrorMediationAdapterError
                                     userInfo:@{NSLocalizedDescriptionKey:
                                             @"Adapter not initialized"}];
    [self.rewardConnector adapter:self didFailToSetUpRewardBasedVideoAdWithError:error];
}

- (void)failedToLoadRewardedPlacement{
    NSError *error = [NSError errorWithDomain:kGADErrorDomain
                                         code:kGADErrorNoFill
                                     userInfo:@{NSLocalizedDescriptionKey:
                                             @"No Ads Available"}];
    [self.rewardConnector adapter:self didFailToLoadRewardBasedVideoAdwithError:error];
}

- (void)failedToLoadInterstitialPlacement{
    NSError *error = [NSError errorWithDomain:kGADErrorDomain
                                         code:kGADErrorNoFill
                                     userInfo:@{NSLocalizedDescriptionKey:
                                             @"No Ads Available"}];
    [self.delegate customEventInterstitial:self didFailAd:error];
}

@end


