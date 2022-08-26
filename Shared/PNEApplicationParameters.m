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

@interface PNEApplicationParameters ()
@property (readwrite, nonatomic) NSInteger vpnSessionNumber;
@property (readwrite, nonatomic) BOOL showRequiredPurchasePrompt;
@end

@implementation PNEApplicationParameters

+ (instancetype)load:(NSDictionary<NSString *, id> *_Nonnull)params {
    PNEApplicationParameters *instance = [[PNEApplicationParameters alloc] init];
    
    id vpnSessionNumber = params[ApplicationParamKeyVPNSessionNumber];
    if ([vpnSessionNumber isKindOfClass:[NSNumber class]]) {
        instance.vpnSessionNumber = [(NSNumber*)vpnSessionNumber integerValue];
    } else {
        instance.vpnSessionNumber = 0;
    }
    
    id showRequiredPurchasePrompt = params[ApplicationParamKeyShowRequiredPurchasePrompt];
    if ([showRequiredPurchasePrompt isKindOfClass:[NSNumber class]]) {
        instance.showRequiredPurchasePrompt = [(NSNumber*)showRequiredPurchasePrompt boolValue];
    } else {
        // Default value.
        instance.showRequiredPurchasePrompt = FALSE;
    }
    
    return instance;
}

@end
