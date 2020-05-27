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
import Utilities
import StoreKit
import PsiApi

/// `ReceiptReadReason` represents the event that caused the receipt file to be read.
public enum ReceiptReadReason: Equatable {
    case remoteRefresh
    case localRefresh
}

public struct ReceiptState: Equatable {
    
    public var receiptData: ReceiptData?
    
    // remoteReceiptRefreshState holds a strong reference to the `SKReceiptRefreshRequest`
    // object while the request is in progress.
    public var remoteReceiptRefreshState: PendingValue<SKReceiptRefreshRequest, Result<Utilities.Unit, SystemErrorEvent>>
    
    public var remoteRefreshAppReceiptPromises: [Promise<Result<(), SystemErrorEvent>>]
}

extension ReceiptState {
    
    public init() {
        receiptData = .none
        remoteReceiptRefreshState = .completed(.success(.unit))
        remoteRefreshAppReceiptPromises = []
    }
    
    public mutating func fulfillRefreshPromises(_ value: Result<(), SystemErrorEvent>) -> Effect<Never> {
        let refreshPromises = self.remoteRefreshAppReceiptPromises
        self.remoteRefreshAppReceiptPromises = []
        return .fireAndForget {
            fulfillAll(promises: refreshPromises, with: value)
        }
    }
}

public enum ReceiptStateAction {
    case localReceiptRefresh
    case _localReceiptDidRefresh(refreshedData: ReceiptData?)
    /// A remote receipt refresh can open a dialog box to
    case remoteReceiptRefresh(optionalPromise: Promise<Result<(), SystemErrorEvent>>?)
    case _remoteReceiptRefreshResult(Result<(), SystemErrorEvent>)
}
