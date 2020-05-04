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

import Foundation

typealias CustomData = String

enum PsiCashParseError: HashableError {
    case speedBoostParseFailure(message: String)
}

/// PsiCash request header metadata keys.
enum PsiCashRequestMetadataKey: String {
    case clientVersion = "client_version"
    case propagationChannelId = "propagation_channel_id"
    case clientRegion = "client_region"
    case sponsorId = "sponsor_id"
}

struct PsiCashParsed<Value: Equatable>: Equatable {
    let items: [Value]
    let parseErrors: [PsiCashParseError]
}

// MARK: PsiCash data model
struct PsiCashLibData: Equatable {
    let authPackage: PsiCashAuthPackage
    let balance: PsiCashAmount
    let availableProducts: PsiCashParsed<PsiCashPurchasableType>
    let activePurchases: PsiCashParsed<PsiCashPurchasedType>
}

extension PsiCashLibData {
    init() {
        authPackage = .init(withTokenTypes: [])
        balance = .zero()
        availableProducts = .init(items: [], parseErrors: [])
        activePurchases = .init(items: [], parseErrors: [])
    }
}

extension PsiCash {
    
    static func make(flags: DebugFlags) -> PsiCash {
        let psiCashLib = PsiCash()
        if flags.devServers {
            psiCashLib.setValue("dev-api.psi.cash", forKey: "serverHostname")
        }
        return psiCashLib
    }

    func setRequestMetadata() {
        if let appVersion = AppInfo.appVersion() {
            setRequestMetadataAtKey(PsiCashRequestMetadataKey.clientVersion.rawValue,
                                    withValue: appVersion)
        }
        if let propagationChannelId = AppInfo.propagationChannelId() {
            setRequestMetadataAtKey(PsiCashRequestMetadataKey.propagationChannelId.rawValue,
                                    withValue: propagationChannelId)
        }
        if let clientRegion = AppInfo.clientRegion() {
            setRequestMetadataAtKey(PsiCashRequestMetadataKey.clientRegion.rawValue,
                                    withValue: clientRegion)
        }

        if let sponsorId = AppInfo.sponsorId() {
            setRequestMetadataAtKey(PsiCashRequestMetadataKey.sponsorId.rawValue,
                                    withValue: sponsorId)
        }
    }

    func speedBoostAuthorizations() -> Set<SignedAuthorization>? {
        let maybeBase64Auths = self.purchases()?
            .filter { $0.transactionClass == PsiCashTransactionClass.speedBoost.rawValue }
            .compactMap { $0.authorization }

        guard let base64Auths = maybeBase64Auths else {
            return nil
        }
        
        return SignedAuthorization.make(setOfBase64Strings: base64Auths)
    }

    func parsedActivePurchases() -> PsiCashParsed<PsiCashPurchasedType> {
        guard let validPurchases = self.validPurchases() else {
            return .init(items: [], parseErrors: [])
        }

        let purchaseErrorTuple = validPurchases.map
        { p -> (purchase: PsiCashPurchasedType?, error: PsiCashParseError?) in
            switch p.mapToPurchased() {
            case .success(let purchased):
                return (purchased, nil)
            case .failure(let error):
                return (nil, error)
            }
        }

        return .init(items: purchaseErrorTuple.compactMap { $0.purchase },
                     parseErrors: purchaseErrorTuple.compactMap { $0.error })
    }

    func availableProducts() -> PsiCashParsed<PsiCashPurchasableType> {
        guard let purchasePrices = self.purchasePrices() else {
            return .init(items: [], parseErrors: [])
        }

        let purchasableErrorTuple = purchasePrices.map
        { p -> (purchase: PsiCashPurchasableType?, error: PsiCashParseError?) in
            switch p.mapToPurchasable() {
            case .success(let purchasable):
                return (purchasable, nil)
            case .failure(let error):
                return (nil, error)
            }
        }

        return .init(items: purchasableErrorTuple.compactMap { $0.purchase },
                     parseErrors: purchasableErrorTuple.compactMap { $0.error })
    }

    /// This function takes a source of truth for authorizations and explicitly expires
    /// any  authorization stored by PsiCash library that is not in `sourceOfTruth`.
    func expirePurchases(notFoundIn sourceOfTruth: [AuthorizationID]) {
        // Set of Auth ids stored by PsiCash library.
        guard let validPurchases = self.validPurchases() else {
            return
        }

        let psiCashAuthIds = Set(validPurchases.compactMap { purchase -> AuthorizationID? in
            guard let base64Auth = purchase.authorization else {
                return nil
            }
            guard let auth = try? SignedAuthorization.make(base64String: base64Auth) else {
                return nil
            }
            return auth.authorization.id
        })

        // Auth ids in PsiCash library not found in `sourceOfTruth`.
        // These are the authorizations that we're going to expire/remove.
        let authIdsToExpire = psiCashAuthIds.subtracting(sourceOfTruth)

        guard authIdsToExpire.count > 0 else {
            return
        }

        self.removePurchases(Array(authIdsToExpire))
    }

    /// Creates a fully typed representation of the PsiCash data managed by the PsiCash lib.
    func dataModel() -> PsiCashLibData {
        PsiCashLibData(
            authPackage: PsiCashAuthPackage(withTokenTypes: self.validTokenTypes() ?? [String]()),
            balance: PsiCashAmount(nanoPsi: self.balance()?.int64Value ?? 0),
            availableProducts: self.availableProducts(),
            activePurchases: self.parsedActivePurchases()
        )
    }

}

extension PsiCashPurchasePrice {
    func mapToPurchasable() -> Result<PsiCashPurchasableType, PsiCashParseError> {
        PsiCashPurchasableType.from(purchasePrice: self)
    }
}

extension PsiCashPurchase {
    func mapToPurchased() -> Result<PsiCashPurchasedType, PsiCashParseError> {
        PsiCashPurchasedType.from(psiCashPurchase: self)
    }
}

// MARK: Data models

struct PsiCashAmount: Comparable, Hashable, Codable {
    private let _storage: Int64
    var inPsi: Double { Double(_storage) / 1e9 }
    var inNanoPsi: Int64 { _storage}
    var isZero: Bool { _storage == 0 }
    
    init(nanoPsi amount: Int64) {
        _storage = amount
    }

    static func zero() -> Self {
        return .init(nanoPsi: 0)
    }
    
    static func < (lhs: PsiCashAmount, rhs: PsiCashAmount) -> Bool {
        return lhs._storage < rhs._storage
    }
}

func + (lhs: PsiCashAmount, rhs: PsiCashAmount) -> PsiCashAmount {
    return PsiCashAmount(nanoPsi: lhs.inNanoPsi + rhs.inNanoPsi)
}

struct PsiCashAuthPackage: Equatable {
    let hasEarnerToken: Bool
    let hasIndicatorToken: Bool
    let hasSpenderToken: Bool
    
    init(withTokenTypes tokenTypes: [String]) {
        hasEarnerToken = tokenTypes.contains("earner")
        hasIndicatorToken = tokenTypes.contains("indicator")
        hasSpenderToken = tokenTypes.contains("spender")
    }
}

// MARK: PsiCash prooducts

/// PsiCash transaction class raw values.
enum PsiCashTransactionClass: String, Codable, CaseIterable {

    case speedBoost = "speed-boost"

    static func from(transactionClass: String) -> PsiCashTransactionClass {
        switch transactionClass {
        case PsiCashTransactionClass.speedBoost.rawValue:
            return .speedBoost

        default: preconditionFailureFeedbackLog(
            "unknown PsiCash transaction class '\(transactionClass)'")
        }
    }
}

protocol PsiCashProduct: Hashable, Codable {
    var transactionClass: PsiCashTransactionClass { get }
    var distinguisher: String { get }
}

/// Information about a PsiCash product that can be purchased, and its price.
struct PsiCashPurchasable<Product: PsiCashProduct>: Hashable {
    let product: Product
    let price: PsiCashAmount
}

typealias SpeedBoostPurchasable = PsiCashPurchasable<SpeedBoostProduct>

/// A transaction with an expirable authorization that has been made.
struct ExpirableTransaction: Equatable {
    let transactionId: String
    let serverTimeExpiry: Date
    let localTimeExpiry: Date
    let authorization: SignedAuthorization

    // True if expiry date has already passed.
    var expired: Bool {
        return localTimeExpiry.timeIntervalSinceNow <= 0
    }

    static func from(psiCashPurchase purchase: PsiCashPurchase) -> Result<Self, ErrorRepr> {
        guard let serverTimeExpiry = purchase.serverTimeExpiry else {
            return .failure(ErrorRepr(repr: "'serverTimeExpiry' is nil"))
        }
        guard let localTimeExpiry = purchase.localTimeExpiry else {
            return .failure(ErrorRepr(repr: "'localTimeExpiry' is nil"))
        }
        guard let base64Auth = purchase.authorization else {
            return .failure(ErrorRepr(repr: "'authorization' is nil"))
        }
        do {
            guard let authorization = try SignedAuthorization.make(base64String: base64Auth) else {
                return .failure(ErrorRepr(repr: "Failed to decode '\(base64Auth)'"))
            }
            return .success(.init(transactionId: purchase.id,
                                  serverTimeExpiry: serverTimeExpiry,
                                  localTimeExpiry: localTimeExpiry,
                                  authorization: authorization))
        } catch {
            return .failure(ErrorRepr(repr: String(describing: error)))
        }
    }
}

/// Wraps a purchased product with the expirable transaction data.
struct PurchasedExpirableProduct<Product: PsiCashProduct>: Equatable {
    let transaction: ExpirableTransaction
    let product: Product
}

enum PsiCashPurchasedType: Equatable {
    case speedBoost(PurchasedExpirableProduct<SpeedBoostProduct>)

    var speedBoost: PurchasedExpirableProduct<SpeedBoostProduct>? {
        guard case let .speedBoost(value) = self else { return nil }
        return value
    }

    static func from(psiCashPurchase purchase: PsiCashPurchase) -> Result<Self, PsiCashParseError> {
        switch PsiCashTransactionClass.from(transactionClass: purchase.transactionClass) {
        case .speedBoost:
            guard let product = SpeedBoostProduct(distinguisher: purchase.distinguisher) else {
                return .failure(
                    .speedBoostParseFailure(message: """
                        Failed to create 'SpeedBoostProduct' from
                        purchase '\(String(describing: purchase))'
                        """))
            }
            let parsedTransaction = ExpirableTransaction.from(psiCashPurchase: purchase)
            switch parsedTransaction {
            case .success(let expirableTransaction):
                return .success(.speedBoost(
                    PurchasedExpirableProduct<SpeedBoostProduct>(transaction: expirableTransaction,
                                                                 product: product)))
            case .failure(let error):
                return .failure(.speedBoostParseFailure(message: """
                    Failed to create 'ExpirableTransaction' from \
                    purchase '\(error)'
                    """))
            }
        }
    }
}

/// Union of all types of PsiCash products.
enum PsiCashPurchasableType {

    case speedBoost(PsiCashPurchasable<SpeedBoostProduct>)

    var speedBoost: PsiCashPurchasable<SpeedBoostProduct>? {
        guard case let .speedBoost(value) = self else { return .none }
        return value
    }

    static func from(purchasePrice: PsiCashPurchasePrice) -> Result<Self, PsiCashParseError> {
        switch PsiCashTransactionClass.from(transactionClass: purchasePrice.transactionClass) {
        case .speedBoost:
            guard let product = SpeedBoostProduct(distinguisher: purchasePrice.distinguisher) else {
                return .failure(.speedBoostParseFailure(message: purchasePrice.distinguisher))
            }
            return
                .success(
                    .speedBoost(
                        .init(product: product,
                              price: PsiCashAmount(nanoPsi: purchasePrice.price.int64Value))))
        }
    }

}

/// Convenience getters
extension PsiCashPurchasableType {

    /// Returns underlying product transaction class.
    var rawTransactionClass: String {
        switch self {
        case .speedBoost(let purchasable):
            return purchasable.product.transactionClass.rawValue
        }
    }

    /// Returns underlying product distinguisher.
    var distinguisher: String {
        switch self {
        case .speedBoost(let purchasable):
            return purchasable.product.distinguisher
        }
    }

    var price: PsiCashAmount {
        switch self {
        case .speedBoost(let purchasable):
            return purchasable.price
        }
    }
}

extension PsiCashPurchasableType: Hashable {

    func hash(into hasher: inout Hasher) {
        switch self {
        case .speedBoost(let product):
            hasher.combine(PsiCashTransactionClass.speedBoost.rawValue)
            hasher.combine(product)
        }
    }

}

struct SpeedBoostProduct: PsiCashProduct {
    
    static let supportedProducts: [String: Int] = [
        "1hr": 1,
        "2hr": 2,
        "3hr": 3,
        "4hr": 4,
        "5hr": 5,
        "6hr": 6,
        "7hr": 7,
        "8hr": 8,
        "9hr": 9
    ]
    
    let transactionClass: PsiCashTransactionClass = .speedBoost
    let distinguisher: String
    let hours: Int

    /// Initializer fails if provided `distinguisher` is not supported.
    init?(distinguisher: String) {
        self.distinguisher = distinguisher
        guard let hours = Self.supportedProducts[distinguisher] else {
            return nil
        }
        self.hours = hours
    }
}
