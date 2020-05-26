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

extension ExpirableTransaction {
    
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
        guard let base64Data = Data(base64Encoded: base64Auth) else {
            return .failure(
                ErrorRepr(repr: """
                    Failed to create data from base64 encoded string: '\(base64Auth)'
                    """)
            )
        }
        do {
            let decoder = JSONDecoder.makeRfc3339Decoder()
            let decodedAuth = try decoder.decode(SignedAuthorization.self, from: base64Data)
            return .success(.init(transactionId: purchase.id,
                                  serverTimeExpiry: serverTimeExpiry,
                                  localTimeExpiry: localTimeExpiry,
                                  authorization: SignedData(rawData: base64Auth,
                                                            decoded: decodedAuth)))
        } catch {
            return .failure(ErrorRepr(repr: String(describing: error)))
        }
    }
    
}

extension PsiCashPurchasedType {
 
    static func from(psiCashPurchase purchase: PsiCashPurchase) -> Result<Self, PsiCashParseError> {
        switch PsiCashTransactionClass.from(transactionClass: purchase.transactionClass) {
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

extension PsiCashPurchasableType {
    
    static func from(purchasePrice: PsiCashPurchasePrice) -> Result<Self, PsiCashParseError> {
        switch PsiCashTransactionClass.from(transactionClass: purchasePrice.transactionClass) {
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
                        price: PsiCashAmount(nanoPsi: purchasePrice.price.int64Value)
                )))
        }
    }
    
}
