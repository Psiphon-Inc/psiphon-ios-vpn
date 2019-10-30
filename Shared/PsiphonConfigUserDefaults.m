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


#import "PsiphonConfigUserDefaults.h"
#import "PsiphonSettingsViewController.h"
#import "UpstreamProxySettings.h"
#import "SharedConstants.h"


@implementation PsiphonConfigUserDefaults {
    NSUserDefaults *userDefaults;
}

#pragma mark - Public methods

+ (instancetype)sharedInstance {
	static dispatch_once_t once;
	static id sharedInstance;
	dispatch_once(&once, ^{
		sharedInstance = [[self alloc] initWithSuiteName:APP_GROUP_IDENTIFIER];
	});
	return sharedInstance;
}

- (instancetype)initWithSuiteName:(NSString *)suiteName {
    self = [super init];
    if (self) {
        userDefaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
    }
    return self;
}

- (NSString*)egressRegion {
    return [userDefaults stringForKey:PSIPHON_CONFIG_EGRESS_REGION];
}

/*!
 * @return True if new data is saved to disk successfully, FALSE otherwise.
 */
- (BOOL)setEgressRegion:(NSString *)newRegion {
    [self setStringValue:newRegion forKey:PSIPHON_CONFIG_EGRESS_REGION];
    return [userDefaults synchronize];
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *userConfigs = [[NSMutableDictionary alloc] init];

    NSString *egressRegion = [userDefaults stringForKey:PSIPHON_CONFIG_EGRESS_REGION];
    if (egressRegion) {
        [userConfigs setObject:egressRegion forKey:PSIPHON_CONFIG_EGRESS_REGION];
    }

    if ([userDefaults boolForKey:kDisableTimeouts]) {
        [userConfigs setObject:@(0.1) forKey:@"NetworkLatencyMultiplierLambda"];
    }

    NSString *upstreamProxyUrl = [userDefaults stringForKey:PSIPHON_CONFIG_UPSTREAM_PROXY_URL];
    if (upstreamProxyUrl) {
        [userConfigs setObject:upstreamProxyUrl forKey:PSIPHON_CONFIG_UPSTREAM_PROXY_URL];
    }

    id upstreamProxyCustomHeaders = [userDefaults objectForKey:PSIPHON_CONFIG_UPSTREAM_PROXY_CUSTOM_HEADERS];
    if ([upstreamProxyCustomHeaders isKindOfClass:[NSDictionary class]]) {
        NSDictionary *customHeaders = (NSDictionary*)upstreamProxyCustomHeaders;
        if ([customHeaders count] > 0) {
            [userConfigs setObject:customHeaders forKey:PSIPHON_CONFIG_UPSTREAM_PROXY_CUSTOM_HEADERS];
        }
    }

    return userConfigs;
}

#pragma mark - Private methods

/*!
 * @return TRUE if a new value is set, FALSE otherwise.
 */
- (BOOL)setStringValue:(NSString *)value forKey:(NSString *)key {
    NSString *oldValue = [userDefaults stringForKey:key];
    if (![oldValue isEqualToString:value]) {
        [userDefaults setObject:value forKey:key];
        return TRUE;
    }
    return FALSE;
}

@end
