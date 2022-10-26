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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// PNEApplicationParameters(s) keys
extern NSString* ApplicationParamKeyVPNSessionNumber;
extern NSString* ApplicationParamKeyShowRequiredPurchasePrompt;

@interface PNEApplicationParameters : NSObject

/// VPN session number is defined in the NE.
/// Value is `0` before the first connected tunnel.
@property (nonatomic) NSInteger vpnSessionNumber;
@property (readonly, nonatomic) BOOL showRequiredPurchasePrompt;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initDefaults;

- (instancetype)initWithDict:(NSDictionary<NSString *, id> *)values;

/// Returns ApplicationParameters dict given by tunnel-core (or default if none provided),
/// along with `vpnSessionNumber`.
- (NSDictionary<NSString *, id> *_Nonnull)asDictionary;

@end

NS_ASSUME_NONNULL_END
