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

#import <Foundation/Foundation.h>

// Psiphon config keys
#define PSIPHON_CONFIG_EGRESS_REGION @"EgressRegion"
#define PSIPHON_CONFIG_UPSTREAM_PROXY_URL @"UpstreamProxyUrl"
#define PSIPHON_CONFIG_UPSTREAM_PROXY_CUSTOM_HEADERS @"CustomHeaders"

@interface PsiphonConfigUserDefaults : NSObject

+ (instancetype)sharedInstance;
- (instancetype)initWithSuiteName:(NSString *)suiteName;

- (NSString*)egressRegion;
- (BOOL)setEgressRegion:(NSString *)newRegion;

/*!
 *
 * @return Returns dictionary of saved user values for psiphon config,
 *         if no configs are saved, returns an empty dictionary.
 */
- (NSDictionary *)dictionaryRepresentation;

@end

