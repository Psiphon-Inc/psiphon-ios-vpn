//
//  HYPRAdMobVideoAdapter.h
//  HyprMX AdMobSDK Adapter

#import <Foundation/Foundation.h>
#import <GoogleMobileAds/Mediation/GADMAdNetworkAdapterProtocol.h>
extern NSString * const kHyprMXUserIdKey;
extern NSString * const kHyprMXConsentStatusKey;
extern NSString * const kHyprMXServerLabelKey;

@interface HYPRAdMobVideoAdapter : NSObject <GADMRewardBasedVideoAdNetworkAdapter, GADCustomEventInterstitial>
@end
