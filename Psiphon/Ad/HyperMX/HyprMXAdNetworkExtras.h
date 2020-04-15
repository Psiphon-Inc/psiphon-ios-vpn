//
//  HyprMXAdNetworkExtras.h
//  HyprMX AdMobSDK Adapter

#import <Foundation/Foundation.h>
#import <GoogleMobileAds/GADAdNetworkExtras.h>
#import "HYPRAdMobVideoAdapter.h"
@import HyprMX;
@interface HyprMXAdNetworkExtras : NSObject <GADAdNetworkExtras>
@property (strong, nonatomic) NSString *userId;
@property (nonatomic) HyprConsentStatus consentStatus;

- (NSDictionary *)customEventExtrasDictionary;
@end
