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

#import "ContainerDB.h"
#import "NSDate+PSIDateExtension.h"
#import "UserDefaults.h"

#pragma mark - NSUserDefaultsKey

UserDefaultsKey const PrivacyPolicyAcceptedRFC3339StringKey =
    @"ContainerDB.PrivacyPolicyAcceptedRFC3339StringKey";

UserDefaultsKey const EmbeddedEgressRegionsStringArrayKey =
    @"embedded_server_entries_egress_regions";  // legacy key

#pragma mark -

@implementation ContainerDB

- (NSDate *)lastPrivacyPolicyUpdate {
    return [NSDate fromRFC3339String:@"2018-05-15T19:39:57+00:00"];
}

- (NSDate *_Nullable)lastAcceptedPrivacyPolicy {
    NSString *_Nullable dateString = [NSUserDefaults.standardUserDefaults
      stringForKey:PrivacyPolicyAcceptedRFC3339StringKey];

    if (!dateString) {
        return nil;
    }
    
    return [NSDate fromRFC3339String:dateString];
}

- (void)setAcceptedPrivacyPolicy:(NSDate *)privacyPolicyDate {
    NSString *dateString = [privacyPolicyDate RFC3339String];
    [NSUserDefaults.standardUserDefaults setObject:dateString
                                            forKey:PrivacyPolicyAcceptedRFC3339StringKey];
}

- (void)setEmbeddedEgressRegions:(NSArray<NSString *> *_Nullable)regions {
    [NSUserDefaults.standardUserDefaults setObject:regions
                                            forKey:EmbeddedEgressRegionsStringArrayKey];
}

- (NSArray<NSString *> *)embeddedEgressRegions {
    return [NSUserDefaults.standardUserDefaults objectForKey:EmbeddedEgressRegionsStringArrayKey];
}

@end
