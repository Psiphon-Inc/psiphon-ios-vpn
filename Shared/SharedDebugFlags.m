/*
 * Copyright (c) 2023, Psiphon Inc.
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

#import "SharedDebugFlags.h"

#if DEBUG || DEV_RELEASE

NSString * const OnConnectedModeKey = @"OnConnectedMode";

@implementation SharedDebugFlags

- (instancetype)init {
    self = [super init];
    if (self) {
        _onConnectedMode = OnConnectedModeDefault;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.onConnectedMode forKey:OnConnectedModeKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        _onConnectedMode = [coder decodeIntegerForKey:OnConnectedModeKey];
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return TRUE;
}

@end

#endif
