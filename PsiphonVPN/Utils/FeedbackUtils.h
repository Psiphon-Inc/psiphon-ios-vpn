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

NS_ASSUME_NONNULL_BEGIN

@interface FeedbackUtils : NSObject

// Returns startTunnel options dictionary with non-sensitive data.
+ (NSDictionary<NSString *, NSString *> *)
startTunnelOptionsFeedbackLog:(NSDictionary<NSString *, NSObject *> *)options;

// Returns a projection of `dict` with keys from `fieldsToLog` only.
+ (NSDictionary<NSString *, NSString *> *)keepFields:(NSArray<NSString *> *)fieldsToLog
                                            fromDict:(NSDictionary<NSString *, NSObject *> *)dict;

@end

NS_ASSUME_NONNULL_END
