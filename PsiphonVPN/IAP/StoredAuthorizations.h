/*
* Copyright (c) 2020, Psiphon Inc.
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
#import "Authorization.h"

NS_ASSUME_NONNULL_BEGIN

@interface StoredAuthorizations : NSObject

@property (nonatomic, nullable, readonly) Authorization *subscriptionAuth;

@property (nonatomic, nonnull, readonly) NSSet<Authorization *> *nonSubscriptionAuths;

- (instancetype _Nonnull)init NS_UNAVAILABLE;

- (instancetype)initWithPersistedValues NS_DESIGNATED_INITIALIZER;

// Returns Authorization ID of `self.nonSubscriptionAuths`.
- (NSSet<NSString *> *)nonSubscriptionAuthIDs;

// Returns encoded representation of all auths.
- (NSArray<NSString *> *)encoded;

- (BOOL)isEqualToStoredAuthorizations:(StoredAuthorizations *_Nonnull)other;

@end

NS_ASSUME_NONNULL_END
