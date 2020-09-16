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

// Should match all cases defined in PSITokenType
enum PsiCashTokenType: RawRepresentable, CaseIterable {
    
    case earner
    case spender
    case indicator
    case account
    
    init?(rawValue: String) {
        switch rawValue {
        case PSITokenType.earnerTokenType:
            self = .earner
        case PSITokenType.spenderTokenType:
            self = .spender
        case PSITokenType.indicatorTokenType:
            self = .indicator
        case PSITokenType.accountTokenType:
            self = .account
        default:
            return nil
        }
    }
    
    var rawValue: String {
        switch self {
        case .earner:
            return PSITokenType.earnerTokenType
        case .spender:
            return PSITokenType.spenderTokenType
        case .indicator:
            return PSITokenType.indicatorTokenType
        case .account:
            return PSITokenType.accountTokenType
        }
    }
    
}

// Swift wrapper for PSIPsiCashLibWrapper
final class PsiCash {
    
    struct Error: Swift.Error {
        let critical: Bool
        let description: String
        
        fileprivate init?(_ error: PSIError?) {
            guard let error = error else {
                return nil;
            }
            self.critical = error.critical
            self.description = error.description
        }
        
        fileprivate init(_ error: PSIError) {
            self.critical = error.critical
            self.description = error.description
        }
    }
    
    struct NewExpiringPurchaseResponse {
        let status: PSIStatus
        let purchaseResult: Result<PsiCashPurchasedType, PsiCashParseError>?
    }
    
    private let client: PSIPsiCashLibWrapper
    private let feedbackLogger: FeedbackLogger
    
    init(feedbackLogger: FeedbackLogger) {
        self.client = PSIPsiCashLibWrapper()
        self.feedbackLogger = feedbackLogger
    }
    
    var initialized: Bool {
        self.client.initialized()
    }
    
    var validTokenTypes: PsiCashValidTokenTypes {
        
        let tokens = self.client.validTokenTypes()
        
        return PsiCashValidTokenTypes(
            hasEarnerToken: tokens.contains(PsiCashTokenType.earner.rawValue),
            hasSpenderToken: tokens.contains(PsiCashTokenType.spender.rawValue),
            hasIndicatorToken: tokens.contains(PsiCashTokenType.indicator.rawValue),
            hasAccountToken: tokens.contains(PsiCashTokenType.account.rawValue)
        )
    }
    
    var dataModel: PsiCashLibData {
        PsiCashLibData(
            authPackage: self.validTokenTypes,
            isAccount: self.client.isAccount(),
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
        httpRequestFunc: @escaping (PSIHTTPParams) -> PSIHTTPResult,
        test: Bool = false
    ) -> Error? {
        let err = self.client.initialize(withUserAgent: userAgent,
                                          fileStoreRoot: fileStoreRoot,
                                          httpRequestFunc: httpRequestFunc,
                                          test: test)
        return Error(err)
    }
    
    func setRequestMetadata(_ metadata: ClientMetaData) -> Error? {
        var err: PSIError?
        
        err = self.client.setRequestMetadataItem(
            PsiCashRequestMetadataKey.clientVersion.rawValue,
            withValue: metadata.clientVersion
        )
        guard err == nil else {
            return Error(err)
        }
        
        err = self.client.setRequestMetadataItem(
            PsiCashRequestMetadataKey.clientRegion.rawValue,
            withValue: metadata.clientRegion
        )
        guard err == nil else {
            return Error(err)
        }
        
        err = self.client.setRequestMetadataItem(
            PsiCashRequestMetadataKey.propagationChannelId.rawValue,
            withValue: metadata.propagationChannelId
        )
        guard err == nil else {
            return Error(err)
        }
        
        err = self.client.setRequestMetadataItem(
            PsiCashRequestMetadataKey.sponsorId.rawValue,
            withValue: metadata.sponsorId
        )
        guard err == nil else {
            return Error(err)
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
    ) -> Result<[PsiCashParsed<PsiCashPurchasedType>], Error> {
        
        let activePurchasesAuthIds = Set(
            self.client.getPurchases().compactMap(\.authorization?.id))
        
        // authIdsToExpire is auth ids in PsiCash library not found in `sourceOfTruth`.
        // These are the authorizations that will be removed.
        let authIdsToExpire = activePurchasesAuthIds.subtracting(sourceOfTruth)
        
        let psiResult = self.client.removePurchases(withTransactionID: Array(authIdsToExpire))
        
        let result: Result<[PsiCashParsed<PsiCashPurchasedType>], Error>
        if let purchases = psiResult.success {
            result = .success(purchases.map {
                PsiCashPurchasedType.parse(purchase: $0 as! PSIPurchase)
            })
        } else if let failure = psiResult.failure {
            result = .failure(Error(failure))
        } else {
            // Programming fault
            fatalError()
        }
        
        return result
    }
    
    func modifyLandingPage(url: String) -> Result<String, Error> {
        guard let result = Result(client.modifyLandingPage(url)) else {
            // Programming fault
            fatalError()
        }
        return result
    }
    
    func getRewardActivityData() -> Result<CustomData, Error> {
        guard let result = Result(client.getRewardedActivityData()) else {
            // Programming fault
            fatalError()
        }
        return result.map(CustomData.init)
    }
    
    // MARK: API Server Requests

    func refreshState(purchaseClasses: [String]) -> Result<PSIStatus, Error> {
        guard
            let result = Result(client.refreshState(withPurchaseClasses: purchaseClasses))
        else {
            // Programming fault
            fatalError()
        }
        return result
    }
    
    func newExpiringPurchase(
        transactionClass: String, distinguisher: String, expectedPrice: PsiCashAmount
    ) -> Result<NewExpiringPurchaseResponse, Error> {
        
        let result = self.client.newExpiringPurchase(
            withTransactionClass: transactionClass,
            distinguisher: distinguisher,
            expectedPrice: expectedPrice.inNanoPsi
        )
        
        if let success = result.success {
            if let purchase = success.purchase {
                return .success(NewExpiringPurchaseResponse(
                                    status: success.status,
                                    purchaseResult: PsiCashPurchasedType.parse(purchase: purchase)))
            } else {
                return .success(NewExpiringPurchaseResponse(status: success.status,
                                                            purchaseResult: .none))
            }
        } else if let failure = result.failure {
            return .failure(Error(failure))
        } else {
            // Programming fault
            fatalError()
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
 
    static func parse(purchase: PSIPurchase) -> Result<Self, PsiCashParseError> {
        
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

fileprivate extension Result where Success == String, Failure == PsiCash.Error {
    
    init?(_ psiResult: PSIResult<NSString>) {
        if let success = psiResult.success {
            self = .success(String(success))
        } else if let failure = psiResult.failure {
            self = .failure(PsiCash.Error(failure))
        } else {
            return nil
        }
    }
    
}

fileprivate extension Result where Success == PSIStatus, Failure == PsiCash.Error {
    
    init?(_ psiResult: PSIResult<PSIStatusWrapper>) {
        if let success = psiResult.success {
            self = .success(success.status)
        } else if let failure = psiResult.failure {
            self = .failure(Error(failure))
        } else {
            return nil
        }
    }
    
}
