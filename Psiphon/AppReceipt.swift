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

typealias ReceiptReducerEnvironment = (
    appBundle: PsiphonBundle,
    iapStore: (IAPAction) -> Effect<Never>,
    subscriptionStore: (SubscriptionAction) -> Effect<Never>,
    receiptRefreshRequestDelegate: ReceiptRefreshRequestDelegate
)

func receiptReducer(
    state: inout ReceiptState, action: ReceiptStateAction, environment: ReceiptReducerEnvironment
) -> [Effect<ReceiptStateAction>] {
    switch action {
    case .localReceiptRefresh:
        let maybeRefreshedData = ReceiptData.fromLocalReceipt(environment.appBundle)
        
        switch (maybeRefreshedData, state.receiptData) {
        case (nil, _), (_, nil):
            state.receiptData = maybeRefreshedData
            return notifyUpdatedReceiptEffects(maybeRefreshedData, environment: environment)
        case let (.some(refreshedData), .some(currentReceiptData)):
            if refreshedData != currentReceiptData {
                state.receiptData = maybeRefreshedData
                return notifyUpdatedReceiptEffects(maybeRefreshedData, environment: environment)
            } else {
               return []
            }
        }
        
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
                request.delegate = environment.receiptRefreshRequestDelegate
                request.start()
            }
        ]
        
    case .receiptRefreshed(let result):
        var effects = [Effect<ReceiptStateAction>]()
        state.remoteReceiptRefreshState = .completed(result.mapToUnit())
        state.receiptRefereshRequestObject = nil
        
        let refreshedData = join(result.map { ReceiptData.fromLocalReceipt(environment.appBundle) }
            .projectSuccess())

        // Creates effect for fulling receipt refresh promises.
        effects.append(
            state.fulfillRefreshPromises(result).mapNever()
        )
        
        guard refreshedData != state.receiptData else {
            return effects
        }
        state.receiptData = refreshedData
        effects.append(contentsOf:
            notifyUpdatedReceiptEffects(refreshedData, environment: environment)
        )
        return effects
    }
    
}

fileprivate func notifyUpdatedReceiptEffects<NeverAction>(
    _ receiptData: ReceiptData?, environment: ReceiptReducerEnvironment
) -> [Effect<NeverAction>] {
    return [
        environment.subscriptionStore(.updatedReceiptData(receiptData)).mapNever(),
        environment.iapStore(.receiptUpdated(receiptData)).mapNever()
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
