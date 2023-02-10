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

NSString* VPNSessionNumber = @"VPNSessionNumber";
NSString* ShowRequiredPurchasePrompt = @"ShowPurchaseRequiredPrompt";

@implementation PNEApplicationParameters

- (instancetype)init {
    self = [super init];
    if (self) {
        // Default values.
        _vpnSessionNumber = 0;
        _showRequiredPurchasePrompt = FALSE;
    }
    return self;
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [coder encodeInteger:self.vpnSessionNumber forKey:VPNSessionNumber];
    [coder encodeBool:self.showRequiredPurchasePrompt forKey:ShowRequiredPurchasePrompt];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        _vpnSessionNumber = [coder decodeIntegerForKey:VPNSessionNumber];
        _showRequiredPurchasePrompt = [coder decodeBoolForKey:ShowRequiredPurchasePrompt];
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return TRUE;
}

@end
