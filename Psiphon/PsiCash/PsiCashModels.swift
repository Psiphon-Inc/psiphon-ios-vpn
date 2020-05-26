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
import PsiApi

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
        balance = .zero
        availableProducts = .init(items: [], parseErrors: [])
        activePurchases = .init(items: [], parseErrors: [])
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

    static let zero: Self = .init(nanoPsi: 0)
    
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

// MARK: PsiCash products

/// PsiCash transaction class raw values.
enum PsiCashTransactionClass: String, Codable, CaseIterable {

    case speedBoost = "speed-boost"

    static func from(transactionClass: String) -> PsiCashTransactionClass? {
        switch transactionClass {
        case PsiCashTransactionClass.speedBoost.rawValue:
            return .speedBoost
        default:
            return .none
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
    let authorization: SignedData<SignedAuthorization>

    // True if expiry date has already passed.
    var expired: Bool {
        return localTimeExpiry.timeIntervalSinceNow <= 0
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
}

/// Union of all types of PsiCash products.
enum PsiCashPurchasableType {

    case speedBoost(PsiCashPurchasable<SpeedBoostProduct>)

    var speedBoost: PsiCashPurchasable<SpeedBoostProduct>? {
        guard case let .speedBoost(value) = self else { return .none }
        return value
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
