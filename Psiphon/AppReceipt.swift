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
import Promises

struct ReceiptState: Equatable {
    var receiptData: ReceiptData?
    var remoteReceiptRefreshState: Pending<Result<Unit, SystemErrorEvent>>
    var remoteRefreshAppReceiptPromises: [Promise<Result<(), SystemErrorEvent>>]
    
    /// Strong reference to request object.
    var receiptRefereshRequestObject: SKReceiptRefreshRequest?
}

extension ReceiptState {
    init() {
        receiptData = .none
        remoteReceiptRefreshState = .completed(.success(.unit))
        remoteRefreshAppReceiptPromises = []
    }
    
    mutating func fulfillRefreshPromises(_ value: Result<(), SystemErrorEvent>) -> Effect<Never> {
        let refreshPromises = self.remoteRefreshAppReceiptPromises
        self.remoteRefreshAppReceiptPromises = []
        return .fireAndForget {
            fulfillAll(promises: refreshPromises, with: value)
        }
    }
}

enum ReceiptStateAction {
    case localReceiptRefresh
    /// A remote receipt refresh can open a dialog box to
    case remoteReceiptRefresh(optinalPromise: Promise<Result<(), SystemErrorEvent>>?)
    case receiptRefreshed(Result<(), SystemErrorEvent>)
}

func receiptReducer(
    state: inout ReceiptState, action: ReceiptStateAction
) -> [Effect<ReceiptStateAction>] {
    switch action {
    case .localReceiptRefresh:
        let refreshedData = ReceiptData.fromLocalReceipt(Current.appBundle)
        guard refreshedData != state.receiptData else {
            return []
        }
        state.receiptData = refreshedData
        return [ notifyUpdatedReceipt(state.receiptData).mapNever() ]
        
    case .remoteReceiptRefresh(optinalPromise: let optionalPromise):
        if let promise = optionalPromise {
            state.remoteRefreshAppReceiptPromises.append(promise)
        }
        
        // No effects if there is already a pending receipt refresh operation.
        guard case .completed(_) = state.remoteReceiptRefreshState else {
            return []
        }
        
        let request = SKReceiptRefreshRequest()
        state.receiptRefereshRequestObject = request
        return [
            .fireAndForget {
                request.delegate = Current.receiptRefreshDelegate
                request.start()
            }
        ]
        
    case .receiptRefreshed(let result):
        var effects = [Effect<ReceiptStateAction>]()
        state.remoteReceiptRefreshState = .completed(result.mapToUnit())
        state.receiptRefereshRequestObject = nil
        
        let refreshedData = join(result.map { ReceiptData.fromLocalReceipt(Current.appBundle) }
            .projectSuccess())

        // Creates effect for fulling receipt refresh promises.
        effects.append(
            state.fulfillRefreshPromises(result).mapNever()
        )
        
        guard refreshedData != state.receiptData else {
            return effects
        }
        state.receiptData = refreshedData
        effects.append(
            notifyUpdatedReceipt(refreshedData).mapNever()
        )
        return effects
    }
    
}

fileprivate func notifyUpdatedReceipt(_ receiptData: ReceiptData?) -> Effect<Never> {
    .fireAndForget {
        Current.app.store.send(.subscription(.updatedReceiptData(receiptData)))
        Current.app.store.send(.iap(.receiptUpdated))
    }
}

/// Default delegate for StoreKit receipt refresh request: `SKReceiptRefreshRequest`.
class ReceiptRefreshRequestDelegate: StoreDelegate<ReceiptStateAction>, SKRequestDelegate {
    
    func requestDidFinish(_ request: SKRequest) {
        sendOnMain(.receiptRefreshed(.success(())))
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        let errorEvent = ErrorEvent(error as NSError)
        sendOnMain(.receiptRefreshed(.failure(errorEvent)))
    }
    
}

struct ReceiptData: Equatable, Codable {
    let fileSize: Int
    /// Subscription data stored in the receipt.
    /// Nil if no subscription data is found in the receipt.
    let subscription: SubscriptionData?
    let data: Data
    
    /// Parses local app receipt and returns a `RceiptData` object.
    /// If no receipt file is found at path pointed to by the `Bundle` `.none` is returned.
    /// - Note: It is expected for the `Bundle` object to have a valid
    static func fromLocalReceipt(_ appBundle: PsiphonBundle) -> ReceiptData? {
        let receiptURL = appBundle.appStoreReceiptURL
        guard FileManager.default.fileExists(atPath: receiptURL.path) else {
            return .none
        }
        guard let receiptData = AppStoreReceiptData.parseReceipt(receiptURL) else {
            PsiFeedbackLogger.error(withType: "InAppPurchase", message: "parse failed",
                                    object: FatalError(message: "failed to parse app receipt"))
            return .none
        }
        // Validate bundle identifier.
        guard receiptData.bundleIdentifier == appBundle.bundleIdentifier else {
            fatalError("""
                Receipt bundle identifier '\(String(describing: receiptData.bundleIdentifier))'
                does not match app bundle identifier '\(appBundle.bundleIdentifier)'
                """)
        }
        guard let inAppSubscription = receiptData.inAppSubscriptions else {
            return .none
        }
        guard let castedInAppSubscription = inAppSubscription as? [String: Any] else {
            return .none
        }
        
        let subscriptionData =
            SubscriptionData.fromSubsriptionDictionary(castedInAppSubscription)
        
        let data: Data
        do {
            try data = Data(contentsOf: receiptURL)
        } catch {
            PsiFeedbackLogger.error(withType: "InAppPurchase",
                                    message: "failed to read app receipt",
                                    object: error)
            return .none
        }
        
        return ReceiptData(fileSize: receiptData.fileSize as! Int,
                       subscription: subscriptionData,
                       data: data)
    }
    
}
