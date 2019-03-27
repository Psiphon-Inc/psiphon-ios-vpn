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


NS_ASSUME_NONNULL_BEGIN

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
 * @return TRUE if subscription verification server should be contacted, FALSE otherwise.
 */
- (BOOL)shouldUpdateAuthorization;

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
