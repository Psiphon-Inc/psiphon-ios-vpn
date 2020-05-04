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

#import "PsiphonConfigReader.h"
#import "PsiFeedbackLogger.h"

PsiFeedbackLogType const PsiphonConfigLogType = @"PsiphonConfigReader";

// File names
#define EMBEDDED_SERVER_ENTRIES @"embedded_server_entries"
#define PSIPHON_CONFIG @"psiphon_config"

#pragma mark - PsiphonConfigSponsorIDs

@interface PsiphonConfigSponsorIds ()
@property (nonatomic, readwrite) NSString *defaultSponsorId;
@property (nonatomic, readwrite) NSString *subscriptionSponsorId;
@property (nonatomic, readwrite) NSString *checkSubscriptionSponsorId;
@end

@implementation PsiphonConfigSponsorIds
@end

#pragma mark - PsiphonConfig

@interface PsiphonConfigReader ()

@property (nonatomic, readwrite) NSDictionary *configs;
@property (nonatomic, readwrite) PsiphonConfigSponsorIds *sponsorIds;

@end

@implementation PsiphonConfigReader

+ (NSString*)embeddedServerEntriesPath {
    return [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:EMBEDDED_SERVER_ENTRIES];
}

+ (NSString*)psiphonConfigPath {
    return [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:PSIPHON_CONFIG];
}

+ (PsiphonConfigReader *_Nullable)fromConfigFile {

    PsiphonConfigReader *instance = [[PsiphonConfigReader alloc] init];

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *bundledConfigPath = PsiphonConfigReader.psiphonConfigPath;

    if (![fileManager fileExistsAtPath:bundledConfigPath]) {
        [PsiFeedbackLogger errorWithType:PsiphonConfigLogType format:@"file not found"];
        return nil;
    }

    // Read in psiphon_config JSON
    NSData *jsonData = [fileManager contentsAtPath:bundledConfigPath];
    NSError *err = nil;
    instance.configs = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:&err];

    if (err) {
        [PsiFeedbackLogger errorWithType:PsiphonConfigLogType message:@"parse failed" object:err];
        return nil;
    }

    // Reads sponsor ids.
    instance.sponsorIds = [[PsiphonConfigSponsorIds alloc] init];

    instance.sponsorIds.defaultSponsorId = instance.configs[@"SponsorId"];
    NSDictionary *subscriptionConfig = instance.configs[@"subscriptionConfig"];
    instance.sponsorIds.subscriptionSponsorId = subscriptionConfig[@"SponsorId"];
    instance.sponsorIds.checkSubscriptionSponsorId = subscriptionConfig[@"checkSponsorId"];

    return instance;
}

@end
