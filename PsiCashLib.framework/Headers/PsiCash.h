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

//
//  PsiCash.h
//  PsiCashLib
//

#ifndef PsiCash_h
#define PsiCash_h

#import <Foundation/Foundation.h>
#import "Purchase.h"
#import "PurchasePrice.h"


typedef NS_ENUM(NSInteger, PsiCashStatus) {
    PsiCashStatus_Invalid = -1,
    PsiCashStatus_Success = 0,
    PsiCashStatus_ExistingTransaction,
    PsiCashStatus_InsufficientBalance,
    PsiCashStatus_TransactionAmountMismatch,
    PsiCashStatus_TransactionTypeNotFound,
    PsiCashStatus_InvalidTokens,
    PsiCashStatus_ServerError
} NS_ENUM_AVAILABLE_IOS(6_0);


// NOTE: All completion handlers will be called on a single serial dispatch queue.
// They will be made asynchronously unless otherwise noted.
// (If it would be better for the library consumer to provide the queue, we can
// change the interface to do that.)

@interface PsiCash : NSObject

# pragma mark - Init

- (id _Nonnull)init;

/*! Set values that will be included in the request metadata. This includes
    client_version, client_region, sponsor_id, and propagation_channel_id. */
- (void)setRequestMetadataAtKey:(NSString*_Nonnull)k withValue:(id)v;

# pragma mark - Stored info accessors

/*! Returns the stored valid token types. Like ["spender", "indicator"].
    May be nil or empty. */
- (NSArray<NSString*>*_Nullable)validTokenTypes;
/*! Returns the stored info about whether the user is a tracker or an account. */
- (BOOL)isAccount;
/*! Returns the stored user balance. May be nil. */
- (NSNumber*_Nullable)balance;
/*! Returns the stored purchase prices. May be nil. */
- (NSArray<PsiCashPurchasePrice*>*_Nullable)purchasePrices;
/*! Returns the set of active purchases. May be nil or empty. */
- (NSArray<PsiCashPurchase*>*_Nullable)purchases;
/*! Returns the set of active purchases that are no expired. May be nil or empty. */
- (NSArray<PsiCashPurchase*>*_Nullable)validPurchases;
/*! Get the next expiring purchase (with localTimeExpiry populated). Returns nil
    if there is no outstanding expiring purchase (or no outstanding purchases at
    all). The returned purchase may already be expired. */
- (PsiCashPurchase*_Nullable)nextExpiringPurchase;
/*! Clear out expired purchases. Return the ones that were expired. Returns nil
    if none were expired. */
- (NSArray<PsiCashPurchase*>*_Nullable)expirePurchases;
/*! Force removal of purchases with the given transaction IDs.
    This is to be called when the Psiphon server indicates that a purchase has
    expired (even if the local clock hasn't yet indicated it).
    Can be passed an NSArray literal, like: @code @[id1, id2] @endcode */
- (void)removePurchases:(NSArray<NSString*>*_Nonnull)ids;

/*! Utilizes stored tokens to craft a landing page URL.
    Returns an error if modification is impossible. (In that case the error
    should be logged -- and added to feedback -- and home page opening should
    proceed. */
- (NSError*_Nullable)modifyLandingPage:(NSString*_Nonnull)url
                           modifiedURL:(NSString*_Nullable*_Nonnull)modifiedURL;

/*! Creates a data package that should be included with a webhook for a user
    action that should be rewarded (such as watching a rewarded video).
    NOTE: The resulting string will still need to be encoded for use in a URL.
    Returns an error if there is no earner token available and therefore the
    reward cannot possibly succeed. (Error may also result from a JSON
    serialization problem, but that's very improbable.)
    So, the library user may want to call this _before_ showing the rewarded
    activity, to perhaps decide _not_ to show that activity. An exception may be
    if the Psiphon connection attempt and subsequent RefreshClientState may
    occur _during_ the rewarded activity, so an earner token may be obtained
    before it's complete. */
- (NSError*_Nullable)getRewardedActivityData:(NSString*_Nullable*_Nonnull)dataString;

/*! Returns a dictionary suitable for JSON-serializing that can be included in
    a feedback diagnostic data package. */
-(NSDictionary<NSString*, NSObject*>*_Nonnull)getDiagnosticInfo;

#pragma mark - RefreshState

/*!
 Refreshes the client state. Retrieves info about whether the user has an
 account (vs tracker), balance, valid token types, and purchase prices. After a
 successful request, the retrieved values can be accessed with the accessor
 methods.

 If there are no tokens stored locally (e.g., if this is the first run), then
 new tracker tokens will obtained.

 If the user is/has an Account, then it is possible some tokens will be invalid
 (they expire at different rates). Login may be necessary before spending, etc.
 (It's even possible that validTokenTypes is empty -- i.e., there are no valid
 tokens.)

 If there is no valid indicator token, then balance and purchasePrices will be
 nil, but there may be stored (possibly stale) values that can be used.

 Input parameters:

 • purchaseClasses: The purchase class names for which prices should be retrieved,
   like `@["speed-boost"]`. If nil or empty, no purchase prices will be retrieved.

 Completion handler parameters:

 • status: Request success indicator. See below for possible values.

 • error: If non-nil, the request failed utterly and no other params are valid.

 Possible status codes:

 • PsiCashStatus_Success

 • PsiCashStatus_ServerError: The server returned 500 error response. Note that
   the request has already been retried internally and any further retry should
   not be immediate.

 • PsiCashStatus_Invalid: Error will be non-nil. This indicates that the server
   was totally unreachable or some other unrecoverable error occurred.

 • PsiCashStatus_InvalidTokens: Should never happen (indicates something like
   local storage corruption). The local user ID will be cleared.
 */
- (void)refreshState:(NSArray<NSString*>*_Nonnull)purchaseClasses
      withCompletion:(void (^_Nonnull)(PsiCashStatus status,
                                       NSError*_Nullable error))completionHandler;

#pragma mark - NewTransaction

/*!
 Makes a new transaction for an "expiring-purchase" class, such as "speed-boost".

 Input parameters:

 • transactionClass: The class name of the desired purchase. (Like "speed-boost".)

 • transactionDistinguisher: The distinguisher for the desired purchase. (Like "1hr".)

 • expectedPrice: The expected price of the purchase (previously obtained by refreshState).
   The transaction will fail if the expectedPrice does not match the actual price.

Completion handler parameters:

 • status: Indicates whether the request succeeded or which failure condition occurred.

 • purchase: The resulting purchase. Nil if request was not successful.

 • error: If non-nil, the request failed utterly and no other params are valid.

 Possible status codes:

 • PsiCashStatus_Success: The purchase transaction was successful. All completion
   handler arguments will be valid.

 • PsiCashStatus_ExistingTransaction: There is already a non-expired purchase that
   prevents this purchase from proceeding.

 • PsiCashStatus_InsufficientBalance: The user does not have sufficient Psi to make
   the requested purchase. Stored balance will be updated and UI should be refreshed.

 • PsiCashStatus_TransactionAmountMismatch: The actual purchase price does not match
   expectedPrice, so the purchase cannot proceed. The price list should be updated
   immediately. 

 • PsiCashStatus_TransactionTypeNotFound: A transaction type with the given class and
   distinguisher could not be found. The price list should be updated immediately,
   but it might also indicate an out-of-date app.

 • PsiCashStatus_InvalidTokens: The current auth tokens are invalid.
   TODO: Figure out how to handle this. It shouldn't be a factor for Trackers or MVP.

 • PsiCashStatus_ServerError: An error occurred on the server. Probably report to
   the user and try again later. Note that the request has already been retried
   internally and any further retry should not be immediate.
 */
- (void)newExpiringPurchaseTransactionForClass:(NSString*_Nonnull)transactionClass
                             withDistinguisher:(NSString*_Nonnull)transactionDistinguisher
                             withExpectedPrice:(NSNumber*_Nonnull)expectedPrice
                                withCompletion:(void (^_Nonnull)(PsiCashStatus status,
                                                                 PsiCashPurchase*_Nullable purchase,
                                                                 NSError*_Nullable error))completion;

@end

#endif /* PsiCash_h */
