#import <Foundation/Foundation.h>
#import "HyprMX/HyprMXPlacement.h"

extern NSString * const kHyprMarketplaceAppConfigKeyUserId;
extern NSString * const kHyprServerParamDistID;
extern NSString * const kHyprServerParamPlacement;
extern NSString * const kServerParameterKey;

extern NSString * const kHyprMarketplace_SDKVersion;
extern NSInteger const kHyprMarketplace_BuildNumber;

@interface HYPRAdMobUtils : NSObject
+ (NSDictionary*)decodeServerParameter:(NSString*)serverParameter;
+ (NSString *)adapterVersion;
+ (BOOL)isCompatibleType:(HyprMXPlacementType)type
              forPlacement:(HyprMXPlacement*)placement;
@end