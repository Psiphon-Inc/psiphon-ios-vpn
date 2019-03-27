/*
 * Copyright (c) 2019, Psiphon Inc.
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

#import "SubscriptionData.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "NSDate+Comparator.h"


@implementation SubscriptionData

+ (SubscriptionData *_Nonnull)fromPersistedDefaults {
    SubscriptionData *instance = [[SubscriptionData alloc] init];
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
        NSDictionary *persistedDic = [sharedDB getSubscriptionVerificationDictionary];
        dictionaryRepresentation = [[NSMutableDictionary alloc] initWithDictionary:persistedDic];
    }
    return self;
}

- (BOOL)isEmpty {
    return (dictionaryRepresentation == nil) || ([dictionaryRepresentation count] == 0);
}

- (NSNumber *_Nullable)appReceiptFileSize {
    return dictionaryRepresentation[kAppReceiptFileSize];
}

- (NSArray *_Nullable)pendingRenewalInfo {
    return dictionaryRepresentation[kPendingRenewalInfo];
}

- (Authorization *)authorization {
    return [[Authorization alloc]
                           initWithEncodedAuthorization:dictionaryRepresentation[kSubscriptionAuthorization]];
}

- (BOOL)hasActiveSubscriptionForNow {
    return [self hasActiveAuthorizationForDate:[NSDate date]];
}

- (BOOL)hasActiveAuthorizationForDate:(NSDate *)date {
    if ([self isEmpty]) {
        return FALSE;
    }
    if (!self.authorization) {
        return FALSE;
    }
    return [self.authorization.expires afterOrEqualTo:date];
}

@end
