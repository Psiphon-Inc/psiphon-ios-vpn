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
import PsiApi
import AppStoreIAP

typealias ReceiptReducerEnvironment = (
    feedbackLogger: FeedbackLogger,
    appBundle: PsiphonBundle,
    iapStore: (IAPAction) -> Effect<Never>,
    subscriptionStore: (SubscriptionAction) -> Effect<Never>,
    subscriptionAuthStateStore: (SubscriptionAuthStateAction) -> Effect<Never>,
    receiptRefreshRequestDelegate: ReceiptRefreshRequestDelegate,
    isSupportedProduct: (ProductID) -> AppStoreProductType?,
    dateCompare: DateCompare
)

let receiptReducer = Reducer<ReceiptState, ReceiptStateAction, ReceiptReducerEnvironment> {
    state, action, environment in
    
    switch action {
    case .readLocalReceiptFile:
         return [
            ReceiptData.fromLocalReceipt(environment: environment)
                .map(ReceiptStateAction._readLocalReceiptFile(refreshedData:))
        ]

    case ._readLocalReceiptFile(let updatedReceipt):
        
        switch state.receiptData {
        case .none:
            
            // First time the receipt is read.
            state.receiptData = .some(updatedReceipt)
            
            return notifyUpdatedReceiptData(
                receiptData: updatedReceipt,
                reason: .localUpdate,
                environment: environment
            )
            
        case .some(let current):
            
            if current != updatedReceipt {
                // Content of the receipt have changed.
                
                state.receiptData = .some(updatedReceipt)
                
                return notifyUpdatedReceiptData(
                    receiptData: updatedReceipt,
                    reason: .localUpdate,
                    environment: environment
                )
                
            } else {
                // Content of receipt file have not changed since last read.
                return [
                    environment.feedbackLogger.log(
                        .info, "Receipt file not updated").mapNever()
                ]
            }
            
        }

    case .remoteReceiptRefresh(optionalPromise: let optionalPromise):
        if let promise = optionalPromise {
            state.remoteRefreshAppReceiptPromises.append(promise)
        }

        // No effects if there is already a pending receipt refresh operation.
        guard case .completed(_) = state.remoteReceiptRefreshState else {
            return []
        }

        let request = SKReceiptRefreshRequest()
        state.remoteReceiptRefreshState = .pending(request)
        return [
            .fireAndForget {
                request.delegate = environment.receiptRefreshRequestDelegate
                request.start()
            }
        ]

    case ._remoteReceiptRefreshResult(let result):
        state.remoteReceiptRefreshState = .completed(result)

        return [
            state.fulfillRefreshPromises(result).mapNever(),
            ReceiptData.fromLocalReceipt(environment: environment)
                .map(ReceiptStateAction._readLocalReceiptFile(refreshedData:))
        ]

    }

}

extension ReceiptData {

    fileprivate static func fromLocalReceipt(
        environment: ReceiptReducerEnvironment
    ) -> Effect<ReceiptData?> {
        Effect { () -> ReceiptData? in
            ReceiptData.parseLocalReceipt(
                appBundle: environment.appBundle,
                isSupportedProduct: environment.isSupportedProduct,
                getCurrentTime: environment.dateCompare.getCurrentTime,
                compareDates: environment.dateCompare.compareDates,
                feedbackLogger: environment.feedbackLogger
            )
        }
    }

}

/// Notifies all relevant services of updated receipt.
fileprivate func notifyUpdatedReceiptData<NeverAction>(
    receiptData: ReceiptData?, reason: ReceiptReadReason, environment: ReceiptReducerEnvironment
) -> [Effect<NeverAction>] {
    return [
        
        environment.subscriptionStore(.appReceiptDataUpdated(receiptData)).mapNever(),
        
        environment.subscriptionAuthStateStore(
            .appReceiptDataUpdated(receiptData, reason)
        ).mapNever(),
        
        environment.iapStore(.appReceiptDataUpdated(receiptData)).mapNever(),
        
        environment.feedbackLogger.log(
            .info, LogMessage(stringLiteral: makeFeedbackEntry(receiptData))
        ).mapNever()
        
    ]
}

/// Default delegate for StoreKit receipt refresh request: `SKReceiptRefreshRequest`.
final class ReceiptRefreshRequestDelegate: StoreDelegate<ReceiptStateAction>, SKRequestDelegate {

    func requestDidFinish(_ request: SKRequest) {
        storeSend(._remoteReceiptRefreshResult(.success(.unit)))
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        let errorEvent = ErrorEvent(SystemError<Int>.make(error as NSError), date: Date())
        return storeSend(._remoteReceiptRefreshResult(.failure(errorEvent)))
    }

}
