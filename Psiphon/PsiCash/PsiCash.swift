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

import Foundation
import PsiApi
import PsiCashClient

fileprivate func psiStatusToRefreshStatus(
    _ status: PSIStatus
) -> Result<(), PsiCashRefreshErrorStatus>? {
    switch status {
    case .success:
        return .success(())
    case .serverError:
        return .failure(.serverError)
    case .invalidTokens:
        return .failure(.invalidTokens)
    default:
        return nil
    }
}

fileprivate func psiStatusToNewExpiringPurchaseStatus(
    _ status: PSIStatus
) -> Result<(), PsiCashNewExpiringPurchaseErrorStatus>? {
    switch status {
    case .success:
        return .success(())
    case .existingTransaction:
        return .failure(.existingTransaction)
    case .insufficientBalance:
        return .failure(.insufficientBalance)
    case .transactionAmountMismatch:
        return .failure(.transactionAmountMismatch)
    case .transactionTypeNotFound:
        return .failure(.transactionTypeNotFound)
    case .invalidTokens:
        return .failure(.invalidTokens)
    case .serverError:
        return .failure(.serverError)
    default:
        return nil
    }
}

fileprivate func psiStatusToAccountLoginStatus(_ status: PSIStatus) -> Result<(), PsiCashAccountLoginErrorStatus>? {
    switch status {
    case .success:
        return .success(())
    case .invalidCredentials:
        return .failure(.invalidCredentials)
    case .badRequest:
        return .failure(.badRequest)
    case .serverError:
        return .failure(.serverError)
    default:
        return nil
    }
}

extension PsiCashLibError {
    
    fileprivate init?(_ error: PSIError?) {
        guard let error = error else {
            return nil;
        }
        self.init(critical: error.critical, description: error.description)
    }
    
    fileprivate init(_ error: PSIError) {
        self.init(critical: error.critical, description: error.description)
    }
    
}

extension PsiCashLibError: FeedbackDescription {}

/// `PsiCash` is a thin wrapper around `PSIPsiCashLibWrapper`.
/// This class is mostly concerned with translating the raw data types used by `PSIPsiCashLibWrapper`
/// to those defined in the `PsiCashClient` module.
final class PsiCash {
    
    private let client: PSIPsiCashLibWrapper
    private let feedbackLogger: FeedbackLogger
    
    init(feedbackLogger: FeedbackLogger) {
        self.client = PSIPsiCashLibWrapper()
        self.feedbackLogger = feedbackLogger
    }
    
    var initialized: Bool {
        self.client.initialized()
    }
    
    var accountType: PsiCashAccountType {
        switch (hasTokens: self.client.hasTokens(), isAccount: self.client.isAccount()) {
        case (false, false):
            return .none
        case (true, false):
            return .tracker
        case (false, true):
            return .account(loggedIn: false)
        case (true, true):
            return .account(loggedIn: true)
        }
    }
    
    var dataModel: PsiCashLibData {
        PsiCashLibData(
            accountType: self.accountType,
            balance: PsiCashAmount(nanoPsi: self.client.balance()),
            availableProducts: self.purchasePrices(),
            activePurchases: self.activePurchases()
        )
    }
    
    /// Must be called once, before any other methods except Reset (or behaviour is undefined).
    /// `userAgent` is required and must be non-empty.
    /// `fileStoreRoot` is required and must be non-empty. `"."` can be used for the cwd.
    /// `httpRequestFunc` may be null and set later with SetHTTPRequestFn.
    /// Returns error if there's an unrecoverable error (such as an inability to use the
    /// filesystem).
    /// If `test` is true, then the test server will be used, and other testing interfaces
    /// will be available. Should only be used for testing.
    /// When uninitialized, data accessors will return zero values, and operations (e.g.,
    /// RefreshState and NewExpiringPurchase) will return errors.
    func initialize(
        userAgent: String,
        fileStoreRoot: String,
        psiCashLegacyDataStore: UserDefaults,
        httpRequestFunc: @escaping (PSIHttpRequest) -> PSIHttpResult,
        forceReset: Bool = false,
        test: Bool = false
    ) -> Result<Bool, PsiCashLibError> {
        let maybeError = PsiCashLibError(
            self.client.initialize(
                withUserAgent: userAgent,
                fileStoreRoot: fileStoreRoot,
                httpRequestFunc: httpRequestFunc,
                forceReset: forceReset,
                test: test
            )
        )

        if let error = maybeError {
            return .failure(error)
        }

        return self.migrateTrackerTokens(legacyDataStore: psiCashLegacyDataStore)
    }
    
    /// Resets PsiCash data for the current user (Tracker or Account). This will typically
    /// be called when wanting to revert to a Tracker from a previously logged in Account.
    func resetUser() -> Error? {
        PsiCashLibError(self.client.resetUser())
    }
    
    /// Forces the given tokens and account status to be set in the datastore. Must be
    /// called after Init(). RefreshState() must be called after method (and shouldn't be
    /// be called before this method, although behaviour will be okay).
    ///
    /// - Returns: Bool if refresh state is required after a successful migration, otherwise returns error due to token migration.
    private func migrateTrackerTokens(legacyDataStore: UserDefaults) -> Result<Bool, PsiCashLibError> {

        let psiCashDataStoreMigratedToVersionKey = "Psiphon-PsiCash-DataStore-Migrated-Version"

        let migrationVersion = legacyDataStore.integer(forKey: psiCashDataStoreMigratedToVersionKey)

        switch migrationVersion {
        case 0:
            // Objective-C based PsiCash client lib used NSUserDefaults with the two legacy keys
            // "Psiphon-PsiCash-UserInfo-Tokens" to store PsiCash tokens.
            // An entry in NSUserDefaults with key "Psiphon-PsiCash-UserInfo-IsAccount" was
            // also created, but never used.
            // PsiCash accounts was introduced in the C++ version of the PsiCash client lib,
            // which deprecated the Objective-C based PsiCash client lib.

            // Tracker tokens legacy key
            let TOKENS_DEFAULTS_KEY = "Psiphon-PsiCash-UserInfo-Tokens"

            guard
                let untypedTokens = legacyDataStore.dictionary(forKey: TOKENS_DEFAULTS_KEY),
                let tokens = untypedTokens as? [String: String]
            else {
                // No legacy tokens found to migrate.
                return .success(false)
            }

            let maybeError = PsiCashLibError(self.client.migrateTrackerTokens(tokens))

            if let error = maybeError {
                // Token migration failed.
                return .failure(error)
            }

            legacyDataStore.set(2, forKey: psiCashDataStoreMigratedToVersionKey)
            return .success(true)

        case 2:
            // Has already migrated successfully.
            return .success(false)

        default:
            fatalError()
        }
    }
    
    func setRequestMetadata(_ metadata: ClientMetaData) -> PsiCashLibError? {
        var err: PSIError?
        
        err = self.client.setRequestMetadataItem(
            PsiCashRequestMetadataKey.clientVersion.rawValue,
            withValue: metadata.clientVersion
        )
        guard err == nil else {
            return PsiCashLibError(err)
        }
        
        err = self.client.setRequestMetadataItem(
            PsiCashRequestMetadataKey.clientRegion.rawValue,
            withValue: metadata.clientRegion
        )
        guard err == nil else {
            return PsiCashLibError(err)
        }
        
        err = self.client.setRequestMetadataItem(
            PsiCashRequestMetadataKey.propagationChannelId.rawValue,
            withValue: metadata.propagationChannelId
        )
        guard err == nil else {
            return PsiCashLibError(err)
        }
        
        err = self.client.setRequestMetadataItem(
            PsiCashRequestMetadataKey.sponsorId.rawValue,
            withValue: metadata.sponsorId
        )
        guard err == nil else {
            return PsiCashLibError(err)
        }
    
        return nil
    }
    
    /// Returns all purchase authorizations. If activeOnly is true, only authorizations
    /// for non-expired purchases will be returned.
    func authorizations(activeOnly: Bool = false) -> Set<SignedAuthorizationData> {
        let auths = self.client.getAuthorizationsWithActiveOnly(activeOnly)
        let typed = auths.compactMap { auth -> SignedAuthorizationData? in
            guard let typedValue = auth.toSignedAuthorization() else {
                // Programming fault
                feedbackLogger.fatalError("failed to decode authorization: id: '\(auth.id)'")
                return nil
            }
            return typedValue
        }
        return Set(typed)
    }
    
    func activePurchases() -> [PsiCashParsed<PsiCashPurchasedType>] {
        self.client.activePurchases().map {
            PsiCashPurchasedType.parse(purchase: $0)
        }
    }
    
    func purchasePrices() -> [PsiCashParsed<PsiCashPurchasableType>] {
        self.client.getPurchasePrices().map {
            PsiCashPurchasableType.parse(purchasePrice: $0)
        }
    }
    
    /// This function takes a source-of-truth for authorizations and explicitly expires
    /// any  authorization stored by PsiCash library that is not in `sourceOfTruth`.
    func removePurchases(
        notFoundIn sourceOfTruth: [AuthorizationID]
    ) -> Result<[PsiCashParsed<PsiCashPurchasedType>], PsiCashLibError> {
        
        let activePurchasesAuthIds = Set(
            self.client.getPurchases().compactMap(\.authorization?.id))
        
        // authIdsToExpire is auth ids in PsiCash library not found in `sourceOfTruth`.
        // These are the authorizations that will be removed.
        let authIdsToExpire = activePurchasesAuthIds.subtracting(sourceOfTruth)
        
        let psiResult = self.client.removePurchases(withTransactionID: Array(authIdsToExpire))
        
        let result: Result<[PsiCashParsed<PsiCashPurchasedType>], PsiCashLibError>
        if let purchases = psiResult.success {
            result = .success(purchases.map {
                PsiCashPurchasedType.parse(purchase: $0 as! PSIPurchase)
            })
        } else if let failure = psiResult.failure {
            result = .failure(PsiCashLibError(failure))
        } else {
            // Programming fault
            fatalError()
        }
        
        return result
    }
    
    func modifyLandingPage(url: String) -> Result<String, PsiCashLibError> {
        guard let result = Result(client.modifyLandingPage(url)) else {
            // Programming fault
            fatalError()
        }
        return result
    }
    
    func getRewardActivityData() -> Result<CustomData, PsiCashLibError> {
        guard let result = Result(client.getRewardedActivityData()) else {
            // Programming fault
            fatalError()
        }
        return result.map(CustomData.init)
    }
    
    // MARK: API Server Requests

    /** Copied from PSIPsiCashLibWrapper
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
    func refreshState(
        purchaseClasses: [String]
    ) -> Result<PsiCashLibData, PsiCashRefreshError> {
        guard
            let result = Result(client.refreshState(withPurchaseClasses: purchaseClasses))
        else {
            // Programming fault
            fatalError()
        }
        
        return result.biFlatMap {
            guard let statusResult = psiStatusToRefreshStatus($0) else {
                // Programming fault
                fatalError()
            }
            
            switch statusResult {
            case .success(()):
                return .success(self.dataModel)
            case .failure(let errorStatus):
                return .failure(.errorStatus(errorStatus))
            }
            
        } transformFailure: {
            return .failure(.requestFailed($0))
        }
    }
    
    /** Copied from PSIPsiCashLibWrapper
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
    func newExpiringPurchase(
        purchasable: PsiCashPurchasableType
    ) -> Result<NewExpiringPurchaseResponse, PsiCashNewExpiringPurchaseError> {
        
        let maybeResult = Result(
            self.client.newExpiringPurchase(
                withTransactionClass: purchasable.rawTransactionClass,
                distinguisher: purchasable.distinguisher,
                expectedPrice: purchasable.price.inNanoPsi
            )
        )
        
        guard let result = maybeResult else {
            // Programming fault
            fatalError()
        }
        
        return result.biFlatMap {
            guard let statusResult = psiStatusToNewExpiringPurchaseStatus($0.status) else {
                // Programming fault
                fatalError()
            }
            
            switch statusResult {
            case .success(()):
                guard let purchase = $0.purchase else {
                    // Programming fault
                    fatalError()
                }
                let parsedPurchasedType = PsiCashPurchasedType.parse(purchase: purchase)
                return .success(
                    NewExpiringPurchaseResponse(purchasedType: parsedPurchasedType)
                )
                
            case .failure(let errorStatus):
                return .failure(.errorStatus(errorStatus))
            }
            
        } transformFailure: {
            return .failure(.requestFailed($0))
        }
    }
    
    /** Copied from PSIPsiCashLibWrapper
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
    func accountLogout() -> PsiCashLibError? {
        PsiCashLibError(self.client.accountLogout())
    }
    
    /** Copied from PSIPsiCashLibWrapper
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
    func accountLogin(
        username: String, password: SecretString
    ) -> Result<AccountLoginResponse, PsiCashAccountLoginError> {
        
        password.unsafeMap { passwordValue in
            
            let maybeResult = Result(self.client.accountLogin(withUsername: username,
                                                              andPassword: passwordValue))
            
            guard let result = maybeResult else {
                // Programming fault
                fatalError()
            }
            
            return result.biFlatMap {
                guard let statusResult = psiStatusToAccountLoginStatus($0.status) else {
                    // Programming fault
                    fatalError()
                }
                
                switch statusResult {
                case .success(()):
                    return .success(
                        AccountLoginResponse(
                            lastTrackerMerge: $0.lastTrackerMerge.toOptionalBool ?? false
                        )
                    )
                    
                case .failure(let errorStatus):
                    return .failure(.errorStatus(errorStatus))
                }
                
            } transformFailure: {
                return .failure(.requestFailed($0))
            }
        }
        
    }
    
}

// MARK: Map ObjC types to equivalent Swift types

fileprivate extension PSIAuthorization {
    func toSignedAuthorization() -> SignedAuthorizationData? {
        guard let decoded = try? SignedAuthorization.make(base64String: self.encoded) else {
            return nil
        }
        return SignedData(rawData: self.encoded, decoded: decoded)
    }
}

// MARK: -

extension PsiCashExpirableTransaction {
    
    static func parse(
        purchase: PSIPurchase
    ) -> Result<PsiCashExpirableTransaction, PsiCashParseError> {
        guard
            let iso8601ServerTimeExpiry = purchase.iso8601ServerTimeExpiry,
            let serverTimeExpiry = Date.parse(rfc3339Date: iso8601ServerTimeExpiry)
        else {
            return .failure(.expirableTransactionParseFailure(message: """
                failed to parse '\(String(describing: purchase.iso8601ServerTimeExpiry))'
                with RFC3339 parser
                """))
        }
        guard
            let iso8601LocalTimeExpiry = purchase.iso8601LocalTimeExpiry,
            let localTimeExpiry = Date.parse(rfc3339Date: iso8601LocalTimeExpiry)
        else {
            return .failure(.expirableTransactionParseFailure(message: """
                failed to parse '\(String(describing: purchase.iso8601ServerTimeExpiry))'
                with RFC3339 parser
                """))
        }
        guard let base64Auth = purchase.authorization?.encoded else {
            return .failure(.expirableTransactionParseFailure(message: "'authorization' is nil"))
        }
        guard let base64Data = Data(base64Encoded: base64Auth) else {
            return .failure(
                .expirableTransactionParseFailure(message: """
                    failed to create data from base64 encoded string: '\(base64Auth)'
                    """)
            )
        }
        do {
            let decoder = JSONDecoder.makeRfc3339Decoder()
            let decodedAuth = try decoder.decode(SignedAuthorization.self, from: base64Data)
            
            return .success(
                PsiCashExpirableTransaction(
                    transactionId: purchase.transactionID as String,
                    serverTimeExpiry: serverTimeExpiry,
                    localTimeExpiry: localTimeExpiry,
                    authorization: SignedAuthorizationData(rawData: base64Auth,
                                                           decoded: decodedAuth)
                )
            )
        } catch {
            return .failure(.expirableTransactionParseFailure(
                                message: "json decoding failed: '\(String(describing: error))'"))
        }
    }
    
}

extension PsiCashPurchasedType {
 
    static func parse(purchase: PSIPurchase) -> PsiCashParsed<Self> {
        
        switch PsiCashTransactionClass.parse(transactionClass: purchase.transactionClass) {
        
        case .none:
            return .failure(.speedBoostParseFailure(message: """
                Unknown PsiCash purchase transaction class '\(purchase.transactionClass)'
                """))
            
        case .speedBoost:
            guard let product = SpeedBoostProduct(distinguisher: purchase.distinguisher) else {
                return .failure(
                    .speedBoostParseFailure(message: """
                        Failed to create 'SpeedBoostProduct' from
                        purchase '\(String(describing: purchase))'
                        """))
            }
            
            switch PsiCashExpirableTransaction.parse(purchase: purchase) {
            case .success(let expirableTransaction):
                return .success(.speedBoost(
                    PurchasedExpirableProduct<SpeedBoostProduct>(transaction: expirableTransaction,
                                                                 product: product)))
            case .failure(let error):
                return .failure(.speedBoostParseFailure(message: """
                    Failed to create 'PsiCashExpirableTransaction' from \
                    purchase '\(error)'
                    """))
            }
        }
    }
    
}

fileprivate extension PsiCashPurchasableType {
    
    static func parse(purchasePrice: PSIPurchasePrice) -> Result<Self, PsiCashParseError> {
        switch PsiCashTransactionClass.parse(transactionClass: purchasePrice.transactionClass) {
        case .none:
            return .failure(.speedBoostParseFailure(message:
                "Unknown PsiCash purchase transaction class '\(purchasePrice.transactionClass)'"))
        case .speedBoost:
            guard let product = SpeedBoostProduct(distinguisher: purchasePrice.distinguisher) else {
                return .failure(.speedBoostParseFailure(message: purchasePrice.distinguisher))
            }
            return
                .success(.speedBoost(
                    PsiCashPurchasable(
                        product: product,
                        price: PsiCashAmount(nanoPsi: purchasePrice.price)
                )))
        }
    }
    
}

fileprivate extension Result where Success == String, Failure == PsiCashLibError {
    
    init?(_ psiResult: PSIResult<NSString>) {
        if let success = psiResult.success {
            self = .success(String(success))
        } else if let failure = psiResult.failure {
            self = .failure(PsiCashLibError(failure))
        } else {
            return nil
        }
    }
    
}

fileprivate extension Result where Success == PSIStatus, Failure == PsiCashLibError {
    
    init?(_ psiResult: PSIResult<PSIStatusWrapper>) {
        if let success = psiResult.success {
            self = .success(success.status)
        } else if let failure = psiResult.failure {
            self = .failure(PsiCashLibError(failure))
        } else {
            return nil
        }
    }
    
}

fileprivate extension Result where Success == PSINewExpiringPurchaseResponse,
                                   Failure == PsiCashLibError {
    
    init?(_ psiResult: PSIResult<PSINewExpiringPurchaseResponse>) {
        if let success = psiResult.success {
            self = .success(success)
        } else if let failure = psiResult.failure {
            self = .failure(PsiCashLibError(failure))
        } else {
            return nil
        }
    }
    
}

fileprivate extension Result where Success == PSIAccountLoginResponse,
                                   Failure == PsiCashLibError {
    
    init?(_ psiResult: PSIResult<PSIAccountLoginResponse>) {
        if let success = psiResult.success {
            self = .success(success)
        } else if let failure = psiResult.failure {
            self = .failure(PsiCashLibError(failure))
        } else {
            return nil
        }
    }
    
}
