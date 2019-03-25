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
#import "Authorization.h"
#import "RACSignal.h"
#import "RACSubscriber.h"
#import "MutableSubscriptionData.h"

NS_ASSUME_NONNULL_BEGIN

typedef void(^SubscriptionVerifierCompletionHandler)(NSDictionary *_Nullable dictionary, NSNumber *_Nonnull submittedReceiptFileSize, NSError *_Nullable error);
#define kReceiptRequestTimeOutSeconds       60.0
#define kRemoteVerificationURL              @"https://subscription.psiphon3.com/appstore"

// Subscription verifier response fields
#define kRemoteSubscriptionVerifierSignedAuthorization                @"signed_authorization"
#define kRemoteSubscriptionVerifierRequestDate                        @"request_date"
#define kRemoteSubscriptionVerifierPendingRenewalInfo                 @"pending_renewal_info"
#define kRemoteSubscriptionVerifierPendingRenewalInfoAutoRenewStatus  @"auto_renew_status"

FOUNDATION_EXPORT NSErrorDomain const ReceiptValidationErrorDomain;

typedef NS_ERROR_ENUM(ReceiptValidationErrorDomain, PsiphonReceiptValidationErrorCode) {
    PsiphonReceiptValidationErrorNSURLSessionFailed,
    PsiphonReceiptValidationErrorHTTPFailed,
    PsiphonReceiptValidationErrorInvalidReceipt,
    PsiphonReceiptValidationErrorJSONParseFailed,
};


@interface SubscriptionVerifierService : NSObject

/**
 * Create a signal that returns an item of type SubscriptionCheckEnum.
 * The value returned only reflects subscription information available locally, and should be combined
 * with other sources of information regarding subscription authorization validity to determine
 * if the authorization is valid or whether the subscription verifier server needs to contacted.
 * @return Returns a signal that emits one of SubscriptionCheckEnum enums and then completes immediately.
 */
+ (RACSignal<NSNumber *> *)localSubscriptionCheck;

+ (RACSignal<RACTwoTuple<NSDictionary *, NSNumber *> *> *)updateAuthorizationFromRemote;

@end


typedef NS_ENUM(NSInteger, SubscriptionCheckEnum) {
    SubscriptionCheckShouldUpdateAuthorization,
    SubscriptionCheckHasActiveAuthorization,
    SubscriptionCheckAuthorizationExpired,
};


#pragma mark - Subscription Result Model

FOUNDATION_EXTERN NSErrorDomain const SubscriptionResultErrorDomain;

typedef NS_ERROR_ENUM(SubscriptionResultErrorDomain, SubscriptionResultErrorCode) {
    SubscriptionResultErrorExpired = 100,
    SubscriptionResultErrorInvalidReceipt = 101
};

@interface SubscriptionResultModel : NSObject

@property (nonatomic, readonly, assign) BOOL inProgress;

/** Error with domain SubscriptionResultErrorDomain */
@property (nonatomic, readonly, nullable) NSError *error;

@property (nonatomic, readonly, nullable) NSDictionary *remoteAuthDict;

@property (nonatomic, readonly, nullable) NSNumber *submittedReceiptFileSize;

+ (SubscriptionResultModel *)inProgress;

+ (SubscriptionResultModel *)failed:(SubscriptionResultErrorCode)errorCode;

+ (SubscriptionResultModel *)success:(NSDictionary *_Nullable)remoteAuthDict receiptFileSize:(NSNumber *_Nullable)receiptFileSize;

@end

# pragma mark - Subscription state

/**
 * SubscriptionState class is thread-safe.
 */
@interface SubscriptionState : NSObject

+ (SubscriptionState *)initialStateFromSubscription:(MutableSubscriptionData *)subscription;

- (BOOL)isSubscribedOrInProgress;

- (BOOL)isSubscribed;

- (BOOL)isInProgress;

- (void)setStateSubscribed;

- (void)setStateInProgress;

- (void)setStateNotSubscribed;

- (NSString *)textDescription;

@end

NS_ASSUME_NONNULL_END
