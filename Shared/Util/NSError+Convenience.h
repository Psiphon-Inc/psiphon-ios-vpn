/*
 * Copyright (c) 2018, Psiphon Inc.
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

@interface NSError (Convenience)

+ (instancetype)errorWithDomain:(NSErrorDomain)domain code:(NSInteger)code;

+ (instancetype)errorWithDomain:(NSErrorDomain)domain
                           code:(NSInteger)code
        andLocalizedDescription:(NSString*)localizedDescription;

+ (instancetype)errorWithDomain:(NSErrorDomain)domain
                           code:(NSInteger)code
        andLocalizedDescription:(NSString*)localizedDescription
            withUnderlyingError:(NSError *)error;

+ (instancetype)errorWithDomain:(NSErrorDomain)domain
                           code:(NSInteger)code
            withUnderlyingError:(NSError *)error;

/// Dictionary representation which is JSON serializable with the default implementation
- (NSDictionary<NSString *, id> *)jsonSerializableDictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
