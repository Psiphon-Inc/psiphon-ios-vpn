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
    getCurrentTime: () -> Date,
    compareDates: (Date, Date, Calendar.Component) -> ComparisonResult
)

func receiptReducer(
    state: inout ReceiptState, action: ReceiptStateAction, environment: ReceiptReducerEnvironment
) -> [Effect<ReceiptStateAction>] {
    switch action {
    case .localReceiptRefresh:
         return [
            ReceiptData.fromLocalReceipt(environment: environment)
                .map(ReceiptStateAction._localReceiptDidRefresh(refreshedData:))
        ]

    case ._localReceiptDidRefresh(let refreshedData):

        state.receiptData = refreshedData

        return notifyRefreshedReceiptEffects(
            receiptData: refreshedData,
            reason: .localRefresh,
            environment: environment
        )

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
                .map(ReceiptStateAction._localReceiptDidRefresh(refreshedData:))
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
                getCurrentTime: environment.getCurrentTime,
                compareDates: environment.compareDates,
                feedbackLogger: environment.feedbackLogger
            )
        }
    }

}

fileprivate func notifyRefreshedReceiptEffects<NeverAction>(
    receiptData: ReceiptData?, reason: ReceiptReadReason, environment: ReceiptReducerEnvironment
) -> [Effect<NeverAction>] {
    return [
        environment.subscriptionStore(.updatedReceiptData(receiptData)).mapNever(),
        environment.subscriptionAuthStateStore(
            .localDataUpdate(type: .didRefreshReceiptData(reason))
        ).mapNever(),
        environment.iapStore(.receiptUpdated(receiptData)).mapNever(),
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
        storeSend(._remoteReceiptRefreshResult(.failure(ErrorEvent(SystemError(error)))))
    }

}
