//
//  HyprMXAdNetworkExtras.m
//  HyprMX AdMobSDK Adapter

#import "HyprMXAdNetworkExtras.h"


@implementation HyprMXAdNetworkExtras
- (NSDictionary *)customEventExtrasDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary new];
    if (self.userId) {
        [dict setObject:self.userId forKey:kHyprMXUserIdKey];
    }
    [dict setObject:[NSNumber numberWithInt:self.consentStatus] forKey:kHyprMXConsentStatusKey];
    return [dict copy];
}
@end
