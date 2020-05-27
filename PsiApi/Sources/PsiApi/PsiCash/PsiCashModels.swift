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

public typealias CustomData = String

public enum PsiCashParseError: HashableError {
    case speedBoostParseFailure(message: String)
}

/// PsiCash request header metadata keys.
public enum PsiCashRequestMetadataKey: String {
    case clientVersion = "client_version"
    case propagationChannelId = "propagation_channel_id"
    case clientRegion = "client_region"
    case sponsorId = "sponsor_id"
}

public struct PsiCashParsed<Value: Equatable>: Equatable {
    public let items: [Value]
    public let parseErrors: [PsiCashParseError]
    
    public init(items: [Value], parseErrors: [PsiCashParseError]) {
        self.items = items
        self.parseErrors = parseErrors
    }
    
}

// MARK: PsiCash data model
public struct PsiCashLibData: Equatable {
    public let authPackage: PsiCashAuthPackage
    public let balance: PsiCashAmount
    public let availableProducts: PsiCashParsed<PsiCashPurchasableType>
    public let activePurchases: PsiCashParsed<PsiCashPurchasedType>
    
    public init(
        authPackage: PsiCashAuthPackage,
        balance: PsiCashAmount,
        availableProducts: PsiCashParsed<PsiCashPurchasableType>,
        activePurchases: PsiCashParsed<PsiCashPurchasedType>
    ) {
        self.authPackage = authPackage
        self.balance = balance
        self.availableProducts = availableProducts
        self.activePurchases = activePurchases
    }
    
}

extension PsiCashLibData {
    public init() {
        authPackage = .init(withTokenTypes: [])
        balance = .zero
        availableProducts = .init(items: [], parseErrors: [])
        activePurchases = .init(items: [], parseErrors: [])
    }
}

// MARK: Data models

public struct PsiCashAmount: Comparable, Hashable, Codable {
    private let _storage: Int64
    public var inPsi: Double { Double(_storage) / 1e9 }
    public var inNanoPsi: Int64 { _storage}
    public var isZero: Bool { _storage == 0 }
    
    public init(nanoPsi amount: Int64) {
        _storage = amount
    }

    public static let zero: Self = .init(nanoPsi: 0)
    
    public static func < (lhs: PsiCashAmount, rhs: PsiCashAmount) -> Bool {
        return lhs._storage < rhs._storage
    }
}

public func + (lhs: PsiCashAmount, rhs: PsiCashAmount) -> PsiCashAmount {
    return PsiCashAmount(nanoPsi: lhs.inNanoPsi + rhs.inNanoPsi)
}

public struct PsiCashAuthPackage: Equatable {
    public let hasEarnerToken: Bool
    public let hasIndicatorToken: Bool
    public let hasSpenderToken: Bool
    
    public init(withTokenTypes tokenTypes: [String]) {
        hasEarnerToken = tokenTypes.contains("earner")
        hasIndicatorToken = tokenTypes.contains("indicator")
        hasSpenderToken = tokenTypes.contains("spender")
    }
}

// MARK: PsiCash products

/// PsiCash transaction class raw values.
public enum PsiCashTransactionClass: String, Codable, CaseIterable {

    case speedBoost = "speed-boost"

    public static func from(transactionClass: String) -> PsiCashTransactionClass? {
        switch transactionClass {
        case PsiCashTransactionClass.speedBoost.rawValue:
            return .speedBoost
        default:
            return .none
        }
    }
}

public protocol PsiCashProduct: Hashable, Codable {
    var transactionClass: PsiCashTransactionClass { get }
    var distinguisher: String { get }
}

/// Information about a PsiCash product that can be purchased, and its price.
public struct PsiCashPurchasable<Product: PsiCashProduct>: Hashable {
    public let product: Product
    public let price: PsiCashAmount
    
    public init(product: Product, price: PsiCashAmount) {
        self.product = product
        self.price = price
    }
}

public typealias SpeedBoostPurchasable = PsiCashPurchasable<SpeedBoostProduct>

/// A transaction with an expirable authorization that has been made.
public struct ExpirableTransaction: Equatable {
    
    public let transactionId: String
    public let serverTimeExpiry: Date
    public let localTimeExpiry: Date
    public let authorization: SignedData<SignedAuthorization>

    // True if expiry date has already passed.
    public var expired: Bool {
        return localTimeExpiry.timeIntervalSinceNow <= 0
    }
    
    public init(
        transactionId: String,
        serverTimeExpiry: Date,
        localTimeExpiry: Date,
        authorization: SignedData<SignedAuthorization>
    ) {
        self.transactionId = transactionId
        self.serverTimeExpiry = serverTimeExpiry
        self.localTimeExpiry = localTimeExpiry
        self.authorization = authorization
    }
}

/// Wraps a purchased product with the expirable transaction data.
public struct PurchasedExpirableProduct<Product: PsiCashProduct>: Equatable {
    public let transaction: ExpirableTransaction
    public let product: Product
    
    public init(transaction: ExpirableTransaction, product: Product) {
        self.transaction = transaction
        self.product = product
    }
}

public enum PsiCashPurchasedType: Equatable {
    case speedBoost(PurchasedExpirableProduct<SpeedBoostProduct>)

    public var speedBoost: PurchasedExpirableProduct<SpeedBoostProduct>? {
        guard case let .speedBoost(value) = self else { return nil }
        return value
    }
}

/// Union of all types of PsiCash products.
public enum PsiCashPurchasableType {

    case speedBoost(PsiCashPurchasable<SpeedBoostProduct>)

    public var speedBoost: PsiCashPurchasable<SpeedBoostProduct>? {
        guard case let .speedBoost(value) = self else { return .none }
        return value
    }

}

/// Convenience getters
extension PsiCashPurchasableType {

    /// Returns underlying product transaction class.
    public var rawTransactionClass: String {
        switch self {
        case .speedBoost(let purchasable):
            return purchasable.product.transactionClass.rawValue
        }
    }

    /// Returns underlying product distinguisher.
    public var distinguisher: String {
        switch self {
        case .speedBoost(let purchasable):
            return purchasable.product.distinguisher
        }
    }

    public var price: PsiCashAmount {
        switch self {
        case .speedBoost(let purchasable):
            return purchasable.price
        }
    }
}

extension PsiCashPurchasableType: Hashable {

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .speedBoost(let product):
            hasher.combine(PsiCashTransactionClass.speedBoost.rawValue)
            hasher.combine(product)
        }
    }

}

public struct SpeedBoostProduct: PsiCashProduct {
    
    public static let supportedProducts: [String: Int] = [
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
    
    public let transactionClass: PsiCashTransactionClass = .speedBoost
    public let distinguisher: String
    public let hours: Int

    /// Initializer fails if provided `distinguisher` is not supported.
    public init?(distinguisher: String) {
        self.distinguisher = distinguisher
        guard let hours = Self.supportedProducts[distinguisher] else {
            return nil
        }
        self.hours = hours
    }
}
