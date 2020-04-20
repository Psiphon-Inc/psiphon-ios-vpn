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
#import "PsiFeedbackLogger.h"


PsiFeedbackLogType const MutableSubscriptionDataLogType = @"SubscriptionData";

@implementation ShouldUpdateAuthResult

+ (ShouldUpdateAuthResult *_Nonnull)shouldUpdateAuth:(BOOL)shouldUpdateAuth
                                              reason:(ShouldUpdateAuthReason)reason {
    ShouldUpdateAuthResult *instance = [[ShouldUpdateAuthResult alloc] init];
    instance.shouldUpdateAuth = shouldUpdateAuth;
    instance.reason = reason;
    return instance;
}

+ (NSString *_Nonnull)reasonToString:(ShouldUpdateAuthReason)reason {
    switch (reason) {
        case ShouldUpdateAuthReasonHasActiveAuthorization:
            return @"hasActiveAuthorization";
            break;
        case ShouldUpdateAuthReasonNoReceiptFile:
            return @"noReceiptFile";
            break;
        case ShouldUpdateAuthReasonContainerHasReceiptWithExpiry:
            return @"containerHasReceiptWithExpiry";
            break;
        case ShouldUpdateAuthReasonReceiptHasNoTransactionData:
            return @"receiptHasNoTransactionData";
            break;
        case ShouldUpdateAuthReasonNoLocalData:
            return @"noLocalData";
            break;
        case ShouldUpdateAuthReasonFileSizeChanged:
            return @"fileSizeChanged";
            break;
        case ShouldUpdateAuthReasonSubscriptionWillBeRenewed:
            return @"subscriptionWillBeRenewed";
            break;
        case ShouldUpdateAuthReasonNoUpdateNeeded:
            return @"noUpdateNeeded";
            break;
        case ShouldUpdateAuthReasonForced:
            return @"forced";
            break;
        case ShouldUpdateAuthReasonAuthorizationStatusRejected:
            return @"authorizationStatusRejected";
            break;
        default:
            return @"unknown";
            break;
    }
}

@end

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

- (ShouldUpdateAuthResult*)shouldUpdateAuthorization {

    // If user has an active authorization for date - NO
    if ([self hasActiveAuthorizationForNow]) {
        LOG_DEBUG(@"device has active authorization for date");
        ShouldUpdateAuthResult *result = [ShouldUpdateAuthResult shouldUpdateAuth:NO
                                                                           reason:ShouldUpdateAuthReasonHasActiveAuthorization];
        [PsiFeedbackLogger infoWithType:MutableSubscriptionDataLogType
                                   json:@{@"event": @"shouldUpdateAuth",
                                         @"result": @(result.shouldUpdateAuth),
                                         @"reason": [ShouldUpdateAuthResult reasonToString:result.reason]}];
        return result;
    }

    // If no receipt - NO
    NSURL *appReceiptURL = [NSBundle mainBundle].appStoreReceiptURL;

    const BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:appReceiptURL.path isDirectory:nil];
    if (!exists) {
        LOG_DEBUG(@"receipt does not exist");
        ShouldUpdateAuthResult *result = [ShouldUpdateAuthResult shouldUpdateAuth:NO
                                                                           reason:ShouldUpdateAuthReasonNoReceiptFile];
        [PsiFeedbackLogger infoWithType:MutableSubscriptionDataLogType
                                   json:@{@"event": @"shouldUpdateAuth",
                                          @"result": @(result.shouldUpdateAuth),
                                          @"reason": [ShouldUpdateAuthResult reasonToString:result.reason]}];
        return result;
    }

    PsiphonDataSharedDB *sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:APP_GROUP_IDENTIFIER];

    // Last expiry date recorded by the container still has time left - YES
    NSDate *_Nullable containerReceiptExpiry = [sharedDB getContainerLastSubscriptionReceiptExpiryDate];
    if (containerReceiptExpiry && [containerReceiptExpiry afterOrEqualTo:[NSDate date]]) {
        ShouldUpdateAuthResult *result = [ShouldUpdateAuthResult shouldUpdateAuth:YES
                                                                           reason:ShouldUpdateAuthReasonContainerHasReceiptWithExpiry];
        [PsiFeedbackLogger infoWithType:MutableSubscriptionDataLogType
                                   json:@{@"event": @"shouldUpdateAuth",
                                         @"result": @(result.shouldUpdateAuth),
                                         @"reason": [ShouldUpdateAuthResult reasonToString:result.reason],
                                         @"expiry": [PsiFeedbackLogger safeValue:containerReceiptExpiry]}];
        return result;
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

        return [ShouldUpdateAuthResult shouldUpdateAuth:NO
                                                 reason:ShouldUpdateAuthReasonReceiptHasNoTransactionData];
    }

    // There's receipt but no subscription persisted - YES
    if([self isEmpty]) {
        LOG_DEBUG(@"receipt exist by no subscription persisted");
        ShouldUpdateAuthResult *result = [ShouldUpdateAuthResult shouldUpdateAuth:YES
                                                                           reason:ShouldUpdateAuthReasonNoLocalData];
        [PsiFeedbackLogger infoWithType:MutableSubscriptionDataLogType
                                   json:@{@"event": @"shouldUpdateAuth",
                                           @"result": @(result.shouldUpdateAuth),
                                           @"reason": [ShouldUpdateAuthResult reasonToString:result.reason]}];
        return result;
    }

    // Receipt file size has changed since last check - YES
    if ([currentReceiptFileSize unsignedIntValue] != [self.appReceiptFileSize unsignedIntValue]) {
        LOG_DEBUG(@"receipt file size changed (%@) since last check (%@)",
          currentReceiptFileSize, self.appReceiptFileSize);
        ShouldUpdateAuthResult *result = [ShouldUpdateAuthResult shouldUpdateAuth:YES
                                                                           reason:ShouldUpdateAuthReasonFileSizeChanged];
        [PsiFeedbackLogger infoWithType:MutableSubscriptionDataLogType
                                   json:@{@"event": @"shouldUpdateAuth",
                                           @"result": @(result.shouldUpdateAuth),
                                           @"reason": [ShouldUpdateAuthResult reasonToString:result.reason],
                                           @"oldFileSize": [PsiFeedbackLogger safeValue:self.appReceiptFileSize],
                                           @"newFileSize": [PsiFeedbackLogger safeValue:currentReceiptFileSize]}];
        return result;
    }

    // If expired but user's last known intention was to auto-renew - YES
    if(self.pendingRenewalInfo &&
       [self.pendingRenewalInfo count] == 1 &&
       [self.pendingRenewalInfo[0] isKindOfClass:[NSDictionary class]]) {

        NSString *autoRenewStatus = [self.pendingRenewalInfo[0]
          objectForKey:kRemoteSubscriptionVerifierPendingRenewalInfoAutoRenewStatus];

        if (autoRenewStatus && [autoRenewStatus isEqualToString:@"1"]) {
            LOG_DEBUG(@"subscription expired but user's last known intention is to auto-renew");
            ShouldUpdateAuthResult *result = [ShouldUpdateAuthResult shouldUpdateAuth:YES
                                                                               reason:ShouldUpdateAuthReasonSubscriptionWillBeRenewed];
            [PsiFeedbackLogger infoWithType:MutableSubscriptionDataLogType
                                       json:@{@"event": @"shouldUpdateAuth",
                                             @"result": @(result.shouldUpdateAuth),
                                             @"reason": [ShouldUpdateAuthResult reasonToString:result.reason]}];

            return result;
        }
    }

    LOG_DEBUG(@"authorization update not needed");
    ShouldUpdateAuthResult *result = [ShouldUpdateAuthResult shouldUpdateAuth:NO
                                                                       reason:ShouldUpdateAuthReasonNoUpdateNeeded];
    [PsiFeedbackLogger infoWithType:MutableSubscriptionDataLogType
                               json:@{@"event": @"shouldUpdateAuth",
                                       @"result": @(result.shouldUpdateAuth),
                                       @"reason": [ShouldUpdateAuthResult reasonToString:result.reason]}];

    return result;
}

- (void)updateWithRemoteAuthDict:(NSDictionary *_Nullable)remoteAuthDict
        submittedReceiptFilesize:(NSNumber *_Nonnull)receiptFilesize {

    // Updates subscription dictionary.
    // Sets pending renewal info and authorization to nil if the server sends an empty response.

    [self setAppReceiptFileSize:receiptFilesize];

    [self setPendingRenewalInfo:remoteAuthDict[kRemoteSubscriptionVerifierPendingRenewalInfo]];

    Authorization *_Nullable authorization = [[Authorization alloc]
      initWithEncodedAuthorization:remoteAuthDict[kRemoteSubscriptionVerifierSignedAuthorization]];

    [self setAuthorization:authorization];

    [self persistChanges];
}

@end
