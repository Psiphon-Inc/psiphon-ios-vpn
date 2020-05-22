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
