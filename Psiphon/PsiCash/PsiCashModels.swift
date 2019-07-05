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

/// PsiCash request header metadata keys.
enum PsiCashRequestMetadataKey: String {
    case clientVersion = "client_version"
    case propagationChannelId = "propagation_channel_id"
    case clientRegion = "client_region"
    case sponsorId = "sponsor_id"
}

typealias AuthIDs = Set<String>

// MARK: PsiCash data model
struct PsiCashLibData: Equatable {
    let authPackage: PsiCashAuthPackage
    let balance: PsiCashAmount
    let availableProducts: [PsiCashPurchasable]
    let activePurchases: [Purchase]
}

extension PsiCash {

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

    func speedBoostAuthorizations() -> Set<Authorization>? {
        // TODO! should this be `purchases` or `validPurchases`?
        let auths = self.purchases()?
            .filter { $0.transactionClass == PsiCashTransactionClass.speedBoost.rawValue }
            .compactMap { $0.authorization }

        return Authorization.create(fromEncodedAuthorizations: auths)
    }

    // TODO! this code needs to be audited for correctness.
    func activePurchases(removeMarkedPurchaseAuthIDs markedAuthIDs: AuthIDs) -> [Purchase] {

        let purchaseIdsToRemove = self.purchases()?.compactMap { purchase -> String? in
            guard let auth = Authorization(encodedAuthorization: purchase.authorization) else {
                return nil
            }
            if markedAuthIDs.contains(auth.id) {
                return purchase.id
            }
            return nil
        }

        if let purchaseIdsToRemove = purchaseIdsToRemove {
            self.removePurchases(purchaseIdsToRemove)
        }

        return self.validPurchases()?.map { $0.mapToPurchase() } ?? [Purchase]()
    }

    /// Creates a fully typed representation of the PsiCash data managed by the PsiCash lib.
    func dataModel(markedPurchaseAuthIDs: AuthIDs) -> PsiCashLibData {
        PsiCashLibData(
            authPackage: PsiCashAuthPackage(withTokenTypes: self.validTokenTypes() ?? [String]()),
            balance: PsiCashAmount(nanoPsi: self.balance()?.int64Value ?? 0),
            availableProducts: self.purchasePrices()?
                .map { $0.mapToPurchasable() } ?? [PsiCashPurchasable](),
            activePurchases: activePurchases(removeMarkedPurchaseAuthIDs: markedPurchaseAuthIDs)
        )
    }

}

extension PsiCashPurchase {
    func mapToPurchase() -> Purchase {
        Purchase(transactionId: self.id,
                 product: PsiCashProductType.from(psiCashPurchase: self),
                 serverTimeExpiry: self.serverTimeExpiry,
                 localTimeExpiry: self.localTimeExpiry,
                 authorization: Authorization(encodedAuthorization: self.authorization))
    }
}

extension PsiCashPurchasePrice {
    func mapToPurchasable() -> PsiCashPurchasable {
        PsiCashPurchasable(product: PsiCashProductType.from(psiCashPurchasePrice: self),
                           price: PsiCashAmount(nanoPsi: self.price.int64Value))
    }
}

// MARK: Data models

struct PsiCashAmount: Equatable, Comparable, Codable, Hashable {
    
    private let _storage: Int64
    
    var inPsi: Double {
        // TODO! check precision loss
        Double(_storage) / 1e9
    }
    
    var inNanoPsi: Int64 {
        _storage
    }
    
    init(nanoPsi amount: Int64) {
        _storage = amount
    }
    
    static func < (lhs: PsiCashAmount, rhs: PsiCashAmount) -> Bool {
        return lhs._storage < rhs._storage
    }
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

        default: preconditionFailure(
            "unknown PsiCash transaction class '\(transactionClass)'")
        }
    }
}

protocol PsiCashProduct: Hashable, Codable {
    var transactionClass: PsiCashTransactionClass { get }
    var distinguisher: String { get }
}

/// Information about a PsiCash product that can be purchased, and its price.
/// TODO! make this Codable
struct PsiCashPurchasable: Equatable, Hashable {
    let product: PsiCashProductType
    let price: PsiCashAmount
}

/// Information about a PsiCash purchase that the user has made.
struct Purchase: Equatable {
    let transactionId: String
    let product: PsiCashProductType
    let serverTimeExpiry: Date?
    let localTimeExpiry: Date?
    let authorization: Authorization?
}

// MARK: Concrete products

/// Union of all types of PsiCash products.
enum PsiCashProductType: Equatable, Hashable {

    case speedBoost(SpeedBoostProduct)

    /// Returns underlying product transaction class.
    var rawTransactionClass: String {
        switch self {
        case .speedBoost(let product):
            return product.transactionClass.rawValue
        }
    }

    /// Returns underlying product distinguisher.
    var distinguisher: String {
        switch self {
        case .speedBoost(let product):
            return product.distinguisher
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .speedBoost(let product):
            hasher.combine(PsiCashTransactionClass.speedBoost.rawValue)
            hasher.combine(product)
        }
    }

    static func from(psiCashPurchasePrice purchasePrice: PsiCashPurchasePrice) -> PsiCashProductType {
        switch PsiCashTransactionClass.from(transactionClass: purchasePrice.transactionClass) {
        case .speedBoost:
            return .speedBoost(SpeedBoostProduct(distinguisher: purchasePrice.distinguisher))
        }
    }

    static func from(psiCashPurchase purchase: PsiCashPurchase) -> PsiCashProductType {
        switch PsiCashTransactionClass.from(transactionClass: purchase.transactionClass) {
        case .speedBoost:
            return .speedBoost(SpeedBoostProduct(distinguisher: purchase.distinguisher))
        }
    }

}

struct SpeedBoostProduct: PsiCashProduct {
    let transactionClass: PsiCashTransactionClass = .speedBoost
    let distinguisher: String
    let hours: Int

    init(distinguisher: String) {
        let index = distinguisher.index(distinguisher.endIndex, offsetBy: -2)
        hours = Int(String(distinguisher[..<index]))!
        self.distinguisher = distinguisher
    }
}
