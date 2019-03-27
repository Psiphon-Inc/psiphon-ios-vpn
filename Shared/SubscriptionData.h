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
#import "Authorization.h"
#import "RACSignal.h"

NS_ASSUME_NONNULL_BEGIN

// Subscription dictionary keys
#define kAppReceiptFileSize             @"kAppReceiptFileSize"
#define kPendingRenewalInfo             @"kPendingRenewalInfo"
#define kSubscriptionAuthorization      @"kSubscriptionAuthorization"


@interface SubscriptionData : NSObject {
@protected
    NSMutableDictionary *dictionaryRepresentation;
}

/** App Store subscription receipt file size. */
@property (nonatomic, nullable, readonly) NSNumber *appReceiptFileSize;

/**
 * App Store subscription pending renewal info details.
 * https://developer.apple.com/library/content/releasenotes/General/ValidateAppStoreReceipt/Chapters/ValidateRemotely.html#//apple_ref/doc/uid/TP40010573-CH104-SW2
 */
@property (nonatomic, nullable, readonly) NSArray * pendingRenewalInfo;

/**
 * The current active authorization, or nil if persisted authorization was rejected by the server.
 */
@property (nonatomic, nullable, readonly) Authorization * authorization;

/**
 * Reads NSUserDefaults and wraps the result in an Authorizations instance.
 * The underlying dictionary can only be manipulated by changing the properties of this instance.
 * @attention -persistChanges should be called to persist any changes made to the returned instance to disk.
 * @return An instance of Authorizations class.
 */
+ (SubscriptionData *)fromPersistedDefaults;

/**
 * @return TRUE if underlying dictionary is empty.
 */
- (BOOL)isEmpty;

/**
 * Checks whether there is active subscription against current time.
 * @return TRUE if subscription is active, FALSE otherwise.
 */
- (BOOL)hasActiveSubscriptionForNow;

/**
 * Returns TRUE if subscription authorization is active compared to provided date.
 * @param date Date to compare the authorization expiration to.
 * @return TRUE if subscription is active, FALSE otherwise.
 */
- (BOOL)hasActiveAuthorizationForDate:(NSDate *)date;

@end


NS_ASSUME_NONNULL_END
