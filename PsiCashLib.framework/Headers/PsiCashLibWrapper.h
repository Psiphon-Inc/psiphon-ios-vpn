/*
 * Copyright (c) 2020, Psiphon Inc.
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

#ifndef WARN_UNUSED_RESULT
#define WARN_UNUSED_RESULT __attribute__((warn_unused_result))
#endif

NS_ASSUME_NONNULL_BEGIN

@interface PSIPair<Value> : NSObject

@property (nonatomic) Value first;
@property (nonatomic) Value second;

@end


@interface PSIHttpRequest : NSObject

// "https"
@property (nonatomic, readonly) NSString *scheme;

// "api.psi.cash"
@property (nonatomic, readonly) NSString *hostname;

// 443
@property (nonatomic, readonly) int port;

// "POST, "GET", etc.
@property (nonatomic, readonly) NSString *method;

// "/v1/tracker"
@property (nonatomic, readonly) NSString *path;

// { "User-Agent": "value", ...etc. }
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *headers;

// name-value pairs: [ ["class", "speed-boost"], ["expectedAmount", "-10000"], ... ]
@property (nonatomic, readonly) NSArray<PSIPair<NSString *> *> *query;

// body must be omitted if empty
@property (nonatomic, readonly) NSString *body;

/**
 Creates complete URL including the query string.
 */
- (NSURL *)makeURL;

@end


@interface PSIHttpResult: NSObject

+ (int)CRITICAL_ERROR;
+ (int)RECOVERABLE_ERROR;

- (instancetype)initWithCode:(int)code
                     headers:(NSDictionary<NSString *, NSArray<NSString *> *> *)headers
                        body:(NSString *)body
                       error:(NSString *)error;

// Convenience initializer with `code` set to `CRITICAL_ERROR`, and all other fields
// set to empty string.
- (instancetype)initWithCriticalError;

// Convenience initializer with `code` set to `RECOVERABLE_ERROR`, and all other fields
// set to empty string.
- (instancetype)initWithRecoverableError;

@end


@interface PSIError : NSObject

@property (nonatomic, readonly) BOOL critical;
@property (nonatomic, readonly) NSString *errorDescription;

@end


@interface PSIResult<Value> : NSObject

@property (nonatomic, nullable) Value success;
@property (nonatomic, nullable) PSIError *failure;

@end


@interface PSIAuthorization : NSObject

@property (nonatomic, readonly) NSString *ID;
@property (nonatomic, readonly) NSString *accessType;
@property (nonatomic, readonly) NSString *iso8601Expires;
@property (nonatomic, readonly) NSString *encoded;

@end


@interface PSIPurchasePrice : NSObject

@property (nonatomic, readonly) NSString *transactionClass;
@property (nonatomic, readonly) NSString *distinguisher;
@property (nonatomic, readonly) int64_t price;

@end


@interface PSIPurchase : NSObject

@property (nonatomic, readonly) NSString *transactionID;
@property (nonatomic, readonly) NSString *transactionClass;
@property (nonatomic, readonly) NSString *distinguisher;
@property (nonatomic, readonly, nullable) NSString * iso8601ServerTimeExpiry;
@property (nonatomic, readonly, nullable) NSString * iso8601LocalTimeExpiry;
@property (nonatomic, readonly, nullable) PSIAuthorization * authorization;

@end


// Values should match psicash::Status enum class.
typedef NS_ENUM(NSInteger, PSIStatus) {
    PSIStatusInvalid = -1, // Should never be used if well-behaved
    PSIStatusSuccess = 0,
    PSIStatusExistingTransaction,
    PSIStatusInsufficientBalance,
    PSIStatusTransactionAmountMismatch,
    PSIStatusTransactionTypeNotFound,
    PSIStatusInvalidTokens,
    PSIStatusInvalidCredentials,
    PSIStatusBadRequest,
    PSIStatusServerError
};

@interface PSIStatusWrapper : NSObject

@property (nonatomic, readonly) PSIStatus status;

@end


@interface PSINewExpiringPurchaseResponse : NSObject

@property (nonatomic, readonly) PSIStatus status;
@property (nonatomic, readonly, nullable) PSIPurchase *purchase;

@end


@interface PSIAccountLoginResponse : NSObject

@property (nonatomic, readonly) PSIStatus status;

/// Represents a nullable bool value.
@property (nonatomic, readonly, nullable) NSNumber *lastTrackerMerge;

@end


// Enumeration of possible token types.
@interface PSITokenType : NSObject

@property (class, nonatomic, readonly, nonnull) NSString *earnerTokenType;
@property (class, nonatomic, readonly, nonnull) NSString *spenderTokenType;
@property (class, nonatomic, readonly, nonnull) NSString *indicatorTokenType;
@property (class, nonatomic, readonly, nonnull) NSString *accountTokenType;

@end


@interface PSIPsiCashLibWrapper : NSObject

/// Must be called once, before any other methods (or behaviour is undefined).
/// `user_agent` is required and must be non-empty.
/// `file_store_root` is required and must be non-empty. `"."` can be used for the cwd.
/// `make_http_request_fn` may be null and set later with SetHTTPRequestFn.
/// Returns false if there's an unrecoverable error (such as an inability to use the
/// filesystem).
/// If `force_reset` is true, the datastore will be completely wiped out and reset.
/// If `test` is true, then the test server will be used, and other testing interfaces
/// will be available. Should only be used for testing.
/// When uninitialized, data accessors will return zero values, and operations (e.g.,
/// RefreshState and NewExpiringPurchase) will return errors.
- (PSIError *_Nullable)initializeWithUserAgent:(NSString *)userAgent
                                 fileStoreRoot:(NSString *)fileStoreRoot
                               httpRequestFunc:(PSIHttpResult * (^_Nullable)(PSIHttpRequest *))httpRequestFunc
                                    forceReset:(BOOL)forceReset
                                          test:(BOOL)test WARN_UNUSED_RESULT;

/// Returns true if the library has been successfully initialized (i.e., `initializeWithUserAgent::::` called).
- (BOOL)initialized;

/// Resets PsiCash data for the current user (Tracker or Account). This will typically
/// be called when wanting to revert to a Tracker from a previously logged in Account.
- (PSIError *_Nullable)resetUser;

/// Forces the given tokens and account status to be set in the datastore. Must be
/// called after Init(). RefreshState() must be called after method (and shouldn't be
/// be called before this method, although behaviour will be okay).
- (PSIError *_Nullable)migrateTokens:(NSDictionary<NSString *, NSString *> *)tokens
                           isAccount:(BOOL)isAccount;

/// Set values that will be included in the request metadata. This includes
/// client_version, client_region, sponsor_id, and propagation_channel_id.
- (PSIError *_Nullable)setRequestMetadataItem:(NSString *)key withValue:(NSString *)value WARN_UNUSED_RESULT;

// MARK: Stored info accessors

/// Returns the stored valid token types. Like ["spender", "indicator"].
/// Will be empty if no tokens are available.
- (NSArray<NSString *> *)validTokenTypes;

/// Returns the stored info about whether the user is a Tracker or an Account.
- (BOOL)isAccount;

/// Returns the stored user balance.
- (int64_t)balance;

/// Returns the stored purchase prices.
/// Will be empty if no purchase prices are available.
- (NSArray<PSIPurchasePrice *> *)getPurchasePrices;

/// Returns the set of active purchases, if any.
- (NSArray<PSIPurchase *> *)getPurchases;

/// Returns the set of active purchases that are not expired, if any.
- (NSArray<PSIPurchase *> *)activePurchases;

/// Returns all purchase authorizations. If activeOnly is true, only authorizations
/// for non-expired purchases will be returned.
- (NSArray<PSIAuthorization *> *)getAuthorizationsWithActiveOnly:(BOOL)activeOnly;

/// Returns all purchases that match the given set of Authorization IDs.
- (NSArray<PSIPurchase *> *)getPurchasesByAuthorizationID:(NSArray<NSString *> *)authorizationIDs;

/// Get the next expiring purchase (with local_time_expiry populated).
/// The returned optional will false if there is no outstanding expiring purchase (or
/// no outstanding purchases at all). The returned purchase may already be expired.
- (PSIPurchase *_Nullable)nextExpiringPurchase;

/// Clear out expired purchases. Return the ones that were expired, if any.
- (PSIResult<NSArray<PSIPurchase *> *> *)expirePurchases WARN_UNUSED_RESULT;

/// Force removal of purchases with the given transaction IDs.
/// This is to be called when the Psiphon server indicates that a purchase has
/// expired (even if the local clock hasn't yet indicated it).
/// Returns the removed purchases.
/// No error results if some or all of the transaction IDs are not found.
- (PSIResult<NSArray<PSIPurchase *> *> *)removePurchasesWithTransactionID:(NSArray<NSString *> *)transactionIds WARN_UNUSED_RESULT;

/// Utilizes stored tokens and metadata to craft a landing page URL.
/// Returns an error if modification is impossible. (In that case the error
/// should be logged -- and added to feedback -- and home page opening should
/// proceed with the original URL.)
- (PSIResult<NSString *> *)modifyLandingPage:(NSString *)url;

/// Utilizes stored tokens and metadata (and a configured base URL) to craft a URL
/// where the user can buy PsiCash for real money.
- (PSIResult<NSString *> *)getBuyPsiURL;

/// Creates a data package that should be included with a webhook for a user
/// action that should be rewarded (such as watching a rewarded video).
/// NOTE: The resulting string will still need to be encoded for use in a URL.
/// Returns an error if there is no earner token available and therefore the
/// reward cannot possibly succeed. (Error may also result from a JSON
/// serialization problem, but that's very improbable.)
/// So, the library user may want to call this _before_ showing the rewarded
/// activity, to perhaps decide _not_ to show that activity. An exception may be
/// if the Psiphon connection attempt and subsequent RefreshClientState may
/// occur _during_ the rewarded activity, so an earner token may be obtained
/// before it's complete.
- (PSIResult<NSString *> *)getRewardedActivityData;

/// Returns a string that can be included in a feedback diagnostic data package.
- (NSString *)getDiagnosticInfo;

// MARK: API Server Requests

/**
 Refreshes the client state. Retrieves info about whether the user has an
 Account (vs Tracker), balance, valid token types, and purchase prices. After a
 successful request, the retrieved values can be accessed with the accessor
 methods.
 
 If there are no tokens stored locally (e.g., if this is the first run), then
 new Tracker tokens will obtained.
 
 If the user is/has an Account, then it is possible some tokens will be invalid
 (they expire at different rates). Login may be necessary before spending, etc.
 (It's even possible that validTokenTypes is empty -- i.e., there are no valid
 tokens.)
 
 If there is no valid indicator token, then balance and purchase prices will not
 be retrieved, but there may be stored (possibly stale) values that can be used.
 
 Input parameters:
 
 • purchase_classes: The purchase class names for which prices should be
 retrieved, like `{"speed-boost"}`. If null or empty, no purchase prices will be retrieved.
 
 Result fields:
 
 • error: If set, the request failed utterly and no other params are valid.
 
 • status: Request success indicator. See below for possible values.
 
 Possible status codes:
 
 • Success: Call was successful. Tokens may now be available (depending on if
 IsAccount is true, ValidTokenTypes should be checked, as a login may be required).
 
 • ServerError: The server returned 500 error response. Note that the request has
 already been retried internally and any further retry should not be immediate.
 
 • InvalidTokens: Should never happen (indicates something like
 local storage corruption). The local user state will be cleared.
 */
- (PSIResult<PSIStatusWrapper *> *)
refreshStateWithPurchaseClasses:(NSArray<NSString *> *)purchaseClasses WARN_UNUSED_RESULT;

/**
 Makes a new transaction for an "expiring-purchase" class, such as "speed-boost".
 
 Input parameters:
 
 • transaction_class: The class name of the desired purchase. (Like
 "speed-boost".)
 
 • distinguisher: The distinguisher for the desired purchase. (Like "1hr".)
 
 • expected_price: The expected price of the purchase (previously obtained by RefreshState).
 The transaction will fail if the expected_price does not match the actual price.
 
 Result fields:
 
 • error: If set, the request failed utterly and no other params are valid.
 
 • status: Request success indicator. See below for possible values.
 
 • purchase: The resulting purchase. Null if purchase was not successful (i.e., if
 the `status` is anything except `Status.Success`).
 
 Possible status codes:
 
 • Success: The purchase transaction was successful. The `purchase` field will be non-null.
 
 • ExistingTransaction: There is already a non-expired purchase that prevents this
 purchase from proceeding.
 
 • InsufficientBalance: The user does not have sufficient credit to make the requested
 purchase. Stored balance will be updated and UI should be refreshed.
 
 • TransactionAmountMismatch: The actual purchase price does not match expectedPrice,
 so the purchase cannot proceed. The price list should be updated immediately.
 
 • TransactionTypeNotFound: A transaction type with the given class and distinguisher
 could not be found. The price list should be updated immediately, but it might also
 indicate an out-of-date app.
 
 • InvalidTokens: The current auth tokens are invalid.
 
 • ServerError: An error occurred on the server. Probably report to the user and try
 again later. Note that the request has already been retried internally and any
 further retry should not be immediate.
 */
- (PSIResult<PSINewExpiringPurchaseResponse *> *)
newExpiringPurchaseWithTransactionClass:(NSString *)transactionClass
distinguisher:(NSString *)distinguisher
expectedPrice:(int64_t)expectedPrice WARN_UNUSED_RESULT;

/**
Logs out a currently logged-in account.
An error will be returned in these cases:
• If the user is not an account
• If the request to the server fails
• If the local datastore cannot be updated
These errors should always be logged, but the local state may end up being logged out,
even if they do occur -- such as when the server request fails -- so checks for state
will need to occur.
NOTE: This (usually) does involve a network operation, so wrappers may want to be
asynchronous.
*/
- (PSIError *_Nullable)accountLogout;

/**
Attempts to log the current user into an account. Will attempt to merge any available
Tracker balance.

If success, RefreshState should be called immediately afterward.

Input parameters:
• utf8_username: The username, encoded in UTF-8.
• utf8_password: The password, encoded in UTF-8.

Result fields:
• error: If set, the request failed utterly and no other params are valid.
• status: Request success indicator. See below for possible values.
• last_tracker_merge: If true, a Tracker was merged into the account, and this was
  the last such merge that is allowed -- the user should be informed of this.

Possible status codes:
• Success: The credentials were correct and the login request was successful. There
  are tokens available for future requests.
• InvalidCredentials: One or both of the username and password did not match a known
  Account.
• BadRequest: The data sent to the server was invalid in some way. This should not
  happen in normal operation.
• ServerError: An error occurred on the server. Probably report to the user and try
  again later. Note that the request has already been retried internally and any
  further retry should not be immediate.
*/
- (PSIResult<PSIAccountLoginResponse *> *)accountLoginWithUsername:(NSString *)username
                                                       andPassword:(NSString *)password;

#if DEBUG

// To be used for testing only.
- (PSIError *_Nullable)testRewardWithClass:(NSString *)transactionClass
                             distinguisher:(NSString *)distinguisher WARN_UNUSED_RESULT;

#endif

@end

NS_ASSUME_NONNULL_END
