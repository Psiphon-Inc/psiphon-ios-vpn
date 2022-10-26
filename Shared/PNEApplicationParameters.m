/*
 * Copyright (c) 2022, Psiphon Inc.
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

#import "PNEApplicationParameters.h"

NSString* ApplicationParamKeyVPNSessionNumber = @"VPNSessionNumber";
NSString* ApplicationParamKeyShowRequiredPurchasePrompt = @"ShowPurchaseRequiredPrompt";

@implementation PNEApplicationParameters {
    // Values received directly form tunnel-core.
    NSDictionary<NSString *, id> *values;
}

+ (NSMutableDictionary *)getDefaultDictionary {
    return [NSMutableDictionary dictionaryWithDictionary: @{
        ApplicationParamKeyVPNSessionNumber: @0,
        ApplicationParamKeyShowRequiredPurchasePrompt: @FALSE
    }];
}

- (instancetype)initDefaults {
    self = [super init];
    if (self) {
        // Default values are defined here.
        values = [PNEApplicationParameters getDefaultDictionary];
    }
    return self;
}

- (instancetype)initWithDict:(NSDictionary<NSString *, id> *)values {
    self = [super init];
    if (self) {
        NSMutableDictionary *dict = [PNEApplicationParameters getDefaultDictionary];
        [dict addEntriesFromDictionary:values];
        self->values = dict;
        self->_vpnSessionNumber = [(NSNumber*)dict[ApplicationParamKeyVPNSessionNumber] integerValue];
    }
    return self;
}

- (BOOL)showRequiredPurchasePrompt {
    return [(NSNumber*)values[ApplicationParamKeyShowRequiredPurchasePrompt] boolValue];
}

- (NSDictionary<NSString *, id> *_Nonnull)asDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:values];
    dict[ApplicationParamKeyVPNSessionNumber] = [NSNumber numberWithInteger:self.vpnSessionNumber];
    return  dict;
}

@end
