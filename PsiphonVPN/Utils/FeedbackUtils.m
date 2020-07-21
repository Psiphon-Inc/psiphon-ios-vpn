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


#import "FeedbackUtils.h"
#import "NEBridge.h"

@implementation FeedbackUtils

+ (NSDictionary<NSString *, NSString *> *)
startTunnelOptionsFeedbackLog:(NSDictionary<NSString *, NSObject *> *)options {
    
    NSArray<NSString *> *nonSensitiveFields = @[EXTENSION_OPTION_START_FROM_CONTAINER,
                                                EXTENSION_OPTION_SUBSCRIPTION_CHECK_SPONSOR_ID,
                                                @"is-on-demand"];
    
    return [FeedbackUtils keepFields:nonSensitiveFields
                            fromDict:options];
    
}

+ (NSDictionary<NSString *, NSString *> *)keepFields:(NSArray<NSString *> *)fieldsToLog
                                             fromDict:(NSDictionary<NSString *, NSObject *> *)dict {
        
    NSMutableDictionary<NSString *, NSString *> *nonSensitive = [NSMutableDictionary dictionary];
    
    for (NSString *key in fieldsToLog) {
        if (dict[key] != nil) {
            nonSensitive[key] = [dict[key] description];
        }
    }
    
    return nonSensitive;
}

@end
