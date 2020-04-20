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

#import <Foundation/Foundation.h>
#import "SubscriptionData.h"

/** ShouldUpdateAuthResult reason */
typedef NS_ENUM(NSInteger, ShouldUpdateAuthReason) {
    /** @const ShouldUpdateAuthReasonHasActiveAuthorization The client has an active authorization for the current device date. */
    ShouldUpdateAuthReasonHasActiveAuthorization,
    /** @const ShouldUpdateAuthReasonNoReceiptFile No app receipt found. */
    ShouldUpdateAuthReasonNoReceiptFile,
    /** @const ShouldUpdateAuthReasonContainerHasReceiptWithExpiry Last expiry date recorded by the container still has time left. */
    ShouldUpdateAuthReasonContainerHasReceiptWithExpiry,
    /** @const ShouldUpdateAuthReasonReceiptHasNoTransactionData The receipt has no transaction data on it. */
    ShouldUpdateAuthReasonReceiptHasNoTransactionData,
    /** @const ShouldUpdateAuthReasonNoLocalData There's a receipt but no subscription data persisted. */
    ShouldUpdateAuthReasonNoLocalData,
    /** @const ShouldUpdateAuthReasonFileSizeChanged Receipt file size has changed since last check. */
    ShouldUpdateAuthReasonFileSizeChanged,
    /** @const ShouldUpdateAuthReasonSubscriptionWillBeRenewed Subscription expired but user's last known intention was to auto-renew. */
    ShouldUpdateAuthReasonSubscriptionWillBeRenewed,
    /** @const ShouldUpdateAuthReasonNoUpdateNeeded Authorization update not needed. */
    ShouldUpdateAuthReasonNoUpdateNeeded,
    /** @const ShouldUpdateAuthReasonForced A forced remote subscription check has been triggered. */
    ShouldUpdateAuthReasonForced,
    /** @const ShouldUpdateAuthReasonAuthorizationStatusRejected The server has rejected the current subscription authorization. */
    ShouldUpdateAuthReasonAuthorizationStatusRejected,
    
};

NS_ASSUME_NONNULL_BEGIN

/// Type which represents result from `shouldUpdateAuthorization`
@interface ShouldUpdateAuthResult : NSObject

/// TRUE  if subscription verification server should be contacted, FALSE otherwise
@property (nonatomic, assign) BOOL shouldUpdateAuth;

/// Reason for the value in `shouldUpdateAuth`
@property (nonatomic, assign) ShouldUpdateAuthReason reason;

+ (ShouldUpdateAuthResult *_Nonnull)shouldUpdateAuth:(BOOL)shouldUpdateAuth
                                              reason:(ShouldUpdateAuthReason)reason;

+ (NSString *_Nonnull)reasonToString:(ShouldUpdateAuthReason)reason;

@end

@interface MutableSubscriptionData : SubscriptionData

+ (MutableSubscriptionData *_Nonnull)fromPersistedDefaults;

/**
 * Returns TRUE if Subscription info is missing, the App Store receipt has changed, or we expect
 * the subscription to be renewed.
 * If this method returns TRUE, current subscription information should be deemed stale, and
 * subscription verifier server should be contacted to get latest subscription information.
 *
 * @note This is a blocking function until the new state is persisted.
 *
 * @return ShouldUpdateAuthResult See comments for `ShouldUpdateAuthResult`.
 */
- (ShouldUpdateAuthResult*)shouldUpdateAuthorization;

/**
 * Convenience method for updating current subscription instance from the dictionary
 * returned by the subscription verifier server.
 *
 * @note This is a blocking function until the new state is persisted.
 *
 * @param remoteAuthDict Dictionary returned from the subscription verifier server.
 * @param receiptFilesize File size of the receipt submitted to the subscription verifier server.
 */
- (void)updateWithRemoteAuthDict:(NSDictionary *_Nullable)remoteAuthDict
        submittedReceiptFilesize:(NSNumber *)receiptFilesize;

@end

NS_ASSUME_NONNULL_END
