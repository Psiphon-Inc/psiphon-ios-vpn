#import <Foundation/Foundation.h>

typedef void (^HYPRInitCompletetionHandler)(BOOL didCompleteSuccessfully);


@interface HYPRInitializationManager : NSObject <HyprMXInitializationDelegate>

@property (nonatomic, strong) NSString *hyprUserId;
@property (nonatomic, strong) NSString *hyprDistributorId;
@property (nonatomic) HyprConsentStatus hyprConsentStatus;
@property (atomic, strong) NSMutableArray<HYPRInitCompletetionHandler> *completionCallbackBlocks;

+ (HYPRInitializationManager *)sharedInstance;
- (void)initializeSDKWithDistributorId:(NSString *)distributorId consentStatus:(HyprConsentStatus)consentStatus completionHandler:(HYPRInitCompletetionHandler)completionHandler;
+ (void)manageUserIdWithUserID:(NSString *)userID;

@end
