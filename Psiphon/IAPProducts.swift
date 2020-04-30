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
import StoreKit
import Promises
import ReactiveSwift

enum ProductIdError: Error {
    case invalidString(String)
}

struct AppStoreProduct: Hashable {
    let type: AppStoreProductType
    let skProduct: SKProduct

    init(_ skProduct: SKProduct) throws {
        let type = try AppStoreProductType.from(skProduct: skProduct)
        self.type = type
        self.skProduct = skProduct
    }
}

enum AppStoreProductType: String {
    case subscription = "subscriptionProductIds"
    case psiCash = "psiCashProductIds"

    private static func from(productIdentifier: String) throws -> AppStoreProductType {
        if productIdentifier.hasPrefix("ca.psiphon.Psiphon.psicash_") {
            return .psiCash
        }

        if productIdentifier.hasPrefix("ca.psiphon.Psiphon.") {
            return .subscription
        }

        throw ProductIdError.invalidString(productIdentifier)
    }

    static func from(transaction: SKPaymentTransaction) throws -> AppStoreProductType {
        return try from(productIdentifier: transaction.payment.productIdentifier)
    }

    static func from(skProduct: SKProduct) throws -> AppStoreProductType {
        return try from(productIdentifier: skProduct.productIdentifier)
    }
}

struct StoreProductIds {
    let values: Set<String>

    private init(for type: AppStoreProductType, validator: (Set<String>) -> Bool) {
        values = try! plistReader(key: type.rawValue, toType: Set<String>.self)
    }

    static func subscription() -> StoreProductIds {
        return .init(for: .subscription) { ids -> Bool in
            // TODO: do some validation here.
            return true
        }
    }

    static func psiCash() -> StoreProductIds {
        return .init(for: .psiCash) { ids -> Bool in
            // TODO: do some validation here.
            return true
        }
    }
}

enum IAPPendingTransactionState: Equatable {
    case purchasing
    case deferred
}

enum IAPCompletedTransactionState: Equatable {
    case purchased
    case restored
}

/// Refines `SKPaymentTransaction` state.
enum IAPTransactionState: Equatable {
    case pending(IAPPendingTransactionState)
    case completed(Result<IAPCompletedTransactionState, Either<SKError, SystemError>>)
}

extension SKPaymentTransaction {

    /// Stricter typing of transaction state type `SKPaymentTransactionState`.
    var typedTransactionState: IAPTransactionState {
        switch self.transactionState {
        case .purchasing:
            return .pending(.purchasing)
        case .deferred:
            return .pending(.deferred)
        case .purchased:
            return .completed(.success(.purchased))
        case .restored:
            return .completed(.success(.restored))
        case .failed:
            // Error is non-null when state is failed.
            let someError = self.error!
            if let skError = someError as? SKError {
                return .completed(.failure(.left(skError)))
            } else {
                return .completed(.failure(.right(someError as SystemError)))
            }
        @unknown default:
            fatalErrorFeedbackLog("unknown transaction state \(self.transactionState)")
        }
    }

    /// Indicates whether the app receipt has been updated.
    var appReceiptUpdated: Bool {
        // Each case is explicitely typed as returning true or false
        // to ensure function correctness in future updates.
        switch self.typedTransactionState {
        case let .completed(completed):
            switch completed {
            case .success(.purchased): return true
            case .success(.restored): return true
            case .failure(_): return false
            }
        case let .pending(pending):
            switch pending {
            case .deferred: return false
            case .purchasing: return false
            }
        }
    }

}

extension Array where Element == SKPaymentTransaction {

    var appReceiptUpdated: Bool {
        return self.map({ $0.appReceiptUpdated }).contains(true)
    }

}
