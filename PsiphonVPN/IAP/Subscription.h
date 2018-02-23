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

#import "UserDefaults.h"
#import "AuthorizationToken.h"
#import "RACSignal.h"
#import "RACSubscriber.h"

typedef void(^SubscriptionVerifierCompletionHandler)(NSDictionary *_Nullable dictionary, NSNumber *_Nonnull submittedReceiptFileSize, NSError *_Nullable error);
#define kReceiptRequestTimeOutSeconds       60.0
#define kRemoteVerificationURL              @"https://subscription.psiphon3.com/appstore"

// Subscription verifier response fields
#define kRemoteSubscriptionVerifierSignedAuthorization                @"signed_authorization"
#define kRemoteSubscriptionVerifierRequestDate                        @"request_date"
#define kRemoteSubscriptionVerifierPendingRenewalInfo                 @"pending_renewal_info"
#define kRemoteSubscriptionVerifierPendingRenewalInfoAutoRenewStatus  @"auto_renew_status"

FOUNDATION_EXPORT NSErrorDomain _Nonnull const ReceiptValidationErrorDomain;

typedef NS_ERROR_ENUM(ReceiptValidationErrorDomain, PsiphonReceiptValidationErrorCode) {
    PsiphonReceiptValidationErrorNSURLSessionFailed,
    PsiphonReceiptValidationErrorHTTPFailed,
    PsiphonReceiptValidationErrorInvalidReceipt,
    PsiphonReceiptValidationErrorJSONParseFailed,
};


@interface SubscriptionVerifierService : NSObject

+ (RACSignal<NSDictionary *> *_Nonnull)updateSubscriptionAuthorizationTokenFromRemote;

@end


@interface Subscription : NSObject <UserDefaultsModelProtocol>

/** App Store subscription receipt file size. */
@property (nonatomic, nullable, readwrite) NSNumber *appReceiptFileSize;

/**
 * App Store subscription pending renewal info details.
 * https://developer.apple.com/library/content/releasenotes/General/ValidateAppStoreReceipt/Chapters/ValidateRemotely.html#//apple_ref/doc/uid/TP40010573-CH104-SW2
 */
@property (nonatomic, nullable, readwrite) NSArray * pendingRenewalInfo;

@property (nonatomic, nullable, readwrite) AuthorizationToken * authorizationToken;

/**
 * Reads NSUserDefaults and wraps the result in an Authorizations instance.
 * The underlying dictionary can only be manipulated by changing the properties of this instance.
 * @attention -persistChanges should be called to persist any changes made to the returned instance to disk.
 * @return An instance of Authorizations class.
 */
+ (Subscription *_Nonnull)fromPersistedDefaults;

/**
 * @return TRUE if underlying dictionary is empty.
 */
- (BOOL)isEmpty;

/**
 * Persists changes made to this instance to NSUserDefaults.
 * This is a blocking function.
 * @return TRUE if data was saved to disk successfully, FALSE otherwise.
 */
- (BOOL)persistChanges;

/**
 * Returns TRUE if authorization token is active compared to provided date.
 * @param date Date to compare the authorization token expiration to.
 * @return TRUE if subscription is active, FALSE otherwise.
 */
- (BOOL)hasActiveSubscriptionTokenForDate:(NSDate *_Nonnull)date;

/**
 * Returns TRUE if Subscription info is missing, the App Store receipt has changed, or we expect
 * the subscription to be renewed.
 * If this method returns TRUE, current subscription information should be deemed stale, and
 * subscription verifier server should be contacted to get latest subscription information.
 * @return TRUE if subscription verification server should be contacted, FALSE otherwise.
 */
- (BOOL)shouldUpdateSubscriptionToken;

/**
 * Convenience method for updating current subscription instance from the dictionary
 * returned by the subscription verifier server.
 * @param remoteAuthDict Dictionary returned from the subscription verifier server.
 * @return nil if this instance is updated successfully, error otherwise.
 */
- (NSError *_Nullable)updateSubscriptionWithRemoteAuthDict:(NSDictionary *_Nullable)remoteAuthDict;

@end

#pragma mark - Subscription Result Model

FOUNDATION_EXTERN NSErrorDomain _Nonnull const SubscriptionResultErrorDomain;

typedef NS_ERROR_ENUM(SubscriptionResultErrorDomain, SubscriptionResultErrorCode) {
    SubscriptionResultErrorExpired = 100,
    SubscriptionResultErrorInvalidReceipt = 101
};

@interface SubscriptionResultModel : NSObject

/** Error with domain SubscriptionResultErrorDomain */
@property (nonatomic, nullable) NSError *error;

@property (nonatomic, nullable) NSDictionary *remoteAuthDict;

@property (nonatomic, nullable) NSNumber *submittedReceiptFileSize;

+ (SubscriptionResultModel *_Nonnull)failed:(SubscriptionResultErrorCode)errorCode;

+ (SubscriptionResultModel *_Nonnull)success:(NSDictionary *_Nonnull)remoteAuthDict receiptFilSize:(NSNumber *_Nonnull)receiptFileSize;

@end
