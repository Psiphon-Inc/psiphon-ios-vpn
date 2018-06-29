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

/** Container object for sponsor Ids */
@interface PsiphonConfigSponsorIds : NSObject

@property (nonatomic, readonly) NSString *defaultSponsorId;
@property (nonatomic, readonly) NSString *subscriptionSponsorId;
@property (nonatomic, readonly) NSString *checkSubscriptionSponsorId;

@end

/** Wrapper class for reading Psiphon config file */
@interface PsiphonConfigReader : NSObject

@property (class, nonatomic, readonly) NSString *embeddedServerEntriesPath;
@property (class, nonatomic, readonly) NSString *psiphonConfigPath;

@property (nonatomic, readonly) NSDictionary *configs;
@property (nonatomic, readonly) PsiphonConfigSponsorIds *sponsorIds;

+ (PsiphonConfigReader *_Nullable)fromConfigFile;

@end

NS_ASSUME_NONNULL_END
