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

#import "MutableSubscriptionData.h"
#import "Logging.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "NSDate+Comparator.h"
#import "SubscriptionVerifierService.h"

#pragma mark - SubscriptionData additions

@implementation MutableSubscriptionData

+ (MutableSubscriptionData *_Nonnull)fromPersistedDefaults {
    MutableSubscriptionData *instance = [[self alloc] init];
    return instance;
}

- (void)setAppReceiptFileSize:(NSNumber *_Nullable)fileSize {
    dictionaryRepresentation[kAppReceiptFileSize] = fileSize;
}

- (void)setPendingRenewalInfo:(NSArray *)pendingRenewalInfo {
    dictionaryRepresentation[kPendingRenewalInfo] = pendingRenewalInfo;
}

- (void)setAuthorization:(Authorization *)authorization {
    dictionaryRepresentation[kSubscriptionAuthorization] = authorization.base64Representation;
}

- (void)persistChanges {
    PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];
    [sharedDB setSubscriptionVerificationDictionary:dictionaryRepresentation];
}

- (BOOL)shouldUpdateAuthorization {
    // If no receipt - NO
    NSURL *appReceiptURL = [NSBundle mainBundle].appStoreReceiptURL;

    const BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:appReceiptURL.path isDirectory:nil];
    if (!exists) {
        LOG_DEBUG(@"receipt does not exist");
        return NO;
    }

    PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

    // Last expiry date recorded by the container still has time left - YES
    NSDate *_Nullable containerReceiptExpiry = [sharedDB getContainerLastSubscriptionReceiptExpiryDate];
    if (containerReceiptExpiry && [containerReceiptExpiry afterOrEqualTo:[NSDate date]]) {
        return YES;
    }

    NSNumber *currentReceiptFileSize;
    [appReceiptURL getResourceValue:&currentReceiptFileSize forKey:NSURLFileSizeKey error:nil];
    NSNumber *containerEmptyReceiptSize = [sharedDB getContainerEmptyReceiptFileSize];

    // The receipt has no transaction data on it - NO
    if ([containerEmptyReceiptSize unsignedIntValue] == [currentReceiptFileSize unsignedIntValue]) {
        // Treats as expired receipt.
        [self setAppReceiptFileSize: currentReceiptFileSize];
        [self setAuthorization:nil];
        [self persistChanges];

        return NO;
    }

    // There's receipt but no subscription persisted - YES
    if([self isEmpty]) {
        LOG_DEBUG(@"receipt exist by no subscription persisted");
        return YES;
    }

    // Receipt file size has changed since last check - YES
    if ([currentReceiptFileSize unsignedIntValue] != [self.appReceiptFileSize unsignedIntValue]) {
        LOG_DEBUG(@"receipt file size changed (%@) since last check (%@)",
          currentReceiptFileSize, self.appReceiptFileSize);
        return YES;
    }

    // If user has an active authorization for date - NO
    if ([self hasActiveAuthorizationForDate:[NSDate date]]) {
        LOG_DEBUG(@"device has active authorization for date");
        return NO;
    }

    // If expired and pending renewal info is missing - YES
    if(!self.pendingRenewalInfo) {
        LOG_DEBUG(@"pending renewal info is missing");
        return YES;
    }

    // If expired but user's last known intention was to auto-renew - YES
    if([self.pendingRenewalInfo count] == 1
      && [self.pendingRenewalInfo[0] isKindOfClass:[NSDictionary class]]) {

        NSString *autoRenewStatus = [self.pendingRenewalInfo[0]
          objectForKey:kRemoteSubscriptionVerifierPendingRenewalInfoAutoRenewStatus];

        if (autoRenewStatus && [autoRenewStatus isEqualToString:@"1"]) {
            LOG_DEBUG(@"subscription expired but user's last known intention is to auto-renew");
            return YES;
        }
    }

    LOG_DEBUG(@"authorization update not needed");
    return NO;
}

- (void)updateWithRemoteAuthDict:(NSDictionary *_Nullable)remoteAuthDict
        submittedReceiptFilesize:(NSNumber *)receiptFilesize {

    if (!remoteAuthDict) {
        return;
    }

    // Updates subscription dictionary.
    [self setAppReceiptFileSize:receiptFilesize];
    [self setPendingRenewalInfo:remoteAuthDict[kRemoteSubscriptionVerifierPendingRenewalInfo]];
    Authorization *authorization = [[Authorization alloc]
                                                   initWithEncodedAuthorization:remoteAuthDict[kRemoteSubscriptionVerifierSignedAuthorization]];
    [self setAuthorization:authorization];
    [self persistChanges];
}

@end
