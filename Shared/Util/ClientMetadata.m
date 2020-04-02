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

#import "AppInfo.h"
#import "ClientMetadata.h"
#import "PsiFeedbackLogger.h"

NSString * const VerifierSubscriptionCheckClientMetadataHeaderField = @"X-Verifier-Metadata";

PsiFeedbackLogType const ClientMetadataLogType = @"ClientMetadata";

@implementation ClientMetadata

+ (NSString *)jsonString {
    NSMutableDictionary *clientMetadata = [[NSMutableDictionary alloc] init];

    if (AppInfo.clientPlatform) {
        [clientMetadata setObject:AppInfo.clientPlatform forKey:@"client_platform"];
    }

    if (AppInfo.clientRegion) {
        [clientMetadata setObject:AppInfo.clientRegion forKey:@"client_region"];
    }

    if (AppInfo.appVersion) {
        [clientMetadata setObject:AppInfo.appVersion forKey:@"client_version"];
    }

    if (AppInfo.propagationChannelId) {
        [clientMetadata setObject:AppInfo.propagationChannelId forKey:@"propagation_channel_id"];
    }

    if (AppInfo.sponsorId) {
        [clientMetadata setObject:AppInfo.sponsorId forKey:@"sponsor_id"];
    }

    NSError *err;
    NSData *serializedDictionary = [NSJSONSerialization dataWithJSONObject:clientMetadata
                                                                   options:kNilOptions
                                                                     error:&err];
    if (err) {
        [PsiFeedbackLogger errorWithType:ClientMetadataLogType message:@"Failed to serialize client metadata as JSON" object:err];
        return nil;
    }

    NSString *encodedJson = [[NSString alloc] initWithData:serializedDictionary encoding:NSUTF8StringEncoding];

    return encodedJson;
}

@end
