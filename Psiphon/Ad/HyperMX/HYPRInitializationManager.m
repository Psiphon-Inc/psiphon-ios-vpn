@import HyprMX;
#import "HYPRInitializationManager.h"
#import "HYPRAdMobUtils.h"

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

@end