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

/// `ReceiptReadReason` represents the event that caused the receipt file to be read.
enum ReceiptReadReason: Equatable {
    case remoteRefresh
    case localRefresh
}

struct ReceiptState: Equatable {
    
    var receiptData: ReceiptData?
    
    // remoteReceiptRefreshState holds a strong reference to the `SKReceiptRefreshRequest`
    // object while the request is in progress.
    var remoteReceiptRefreshState: PendingValue<SKReceiptRefreshRequest, Result<Unit, SystemErrorEvent>>
    
    var remoteRefreshAppReceiptPromises: [Promise<Result<(), SystemErrorEvent>>]
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
    case _localReceiptDidRefresh(refreshedData: ReceiptData?)
    /// A remote receipt refresh can open a dialog box to
    case remoteReceiptRefresh(optionalPromise: Promise<Result<(), SystemErrorEvent>>?)
    case _remoteReceiptRefreshResult(Result<(), SystemErrorEvent>)
}

typealias ReceiptReducerEnvironment = (
    feedbackLogger: FeedbackLogger,
    appBundle: PsiphonBundle,
    iapStore: (IAPAction) -> Effect<Never>,
    subscriptionStore: (SubscriptionAction) -> Effect<Never>,
    subscriptionAuthStateStore: (SubscriptionAuthStateAction) -> Effect<Never>,
    receiptRefreshRequestDelegate: ReceiptRefreshRequestDelegate,
    consumableProductsIDs: Set<ProductID>,
    subscriptionProductIDs: Set<ProductID>,
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
        state.remoteReceiptRefreshState = .completed(result.mapToUnit())
        
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
                consumableProductIDs: environment.consumableProductsIDs,
                subscriptionProductIDs: environment.subscriptionProductIDs,
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
        storeSend(._remoteReceiptRefreshResult(.success(())))
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        let errorEvent = ErrorEvent(error as NSError)
        storeSend(._remoteReceiptRefreshResult(.failure(errorEvent)))
    }
    
}
