#import "HYPRAdMobUtils.h"

NSString * const kHyprMarketplaceAppConfigKeyUserId = @"hyprMarketplaceAppConfigKeyUserId";
NSString * const kHyprServerParamDistID = @"distributorID";
NSString * const kHyprServerParamPlacement = @"placementName";

// Constant defined as a workaround for GADCustomEventParametersServer not linking in AdMob's SDK above version 7.31.0
NSString * const kServerParameterKey = @"parameter";

// The release build number - corresponds to the matching HyprSDK Version
NSString * const kHyprMarketplace_SDKVersion = @"5.2.0";
// The build number of this adapter
NSInteger const kHyprMarketplace_BuildNumber = 13;

@implementation HYPRAdMobUtils

+ (NSDictionary*)decodeServerParameter:(NSString*)serverParameter {

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

+ (NSString *)adapterVersion {
    return [NSString stringWithFormat:@"%@b%ld", kHyprMarketplace_SDKVersion, kHyprMarketplace_BuildNumber];
}

+ (BOOL)isCompatibleType:(HyprMXPlacementType)type
            forPlacement:(HyprMXPlacement*)placement {
    return placement.placementType == type;
}


@end