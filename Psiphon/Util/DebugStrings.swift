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

/// ObjC does not have the runtime metadata to print the enum case source-level names, so those enums have to be extended by
/// `CustomDebugStringConvertible` or `CustomStringConvertible`.
/// https://forums.swift.org/t/why-is-an-enum-returning-enumname-rather-than-caselabel-for-string-describing/27327/3

extension PsiCashStatus: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        switch self {
        case .invalid: return "invalid"
        case .success: return "success"
        case .existingTransaction: return "existingTransaction"
        case .insufficientBalance: return "insufficientBalance"
        case .transactionAmountMismatch: return "transactionAmountMismatch"
        case .transactionTypeNotFound: return "transactionTypeNotFound"
        case .invalidTokens: return "invalidTokens"
        case .serverError: return "serverError"
        @unknown default: return "unknown(\(self.rawValue))"
        }
    }
    
}

extension AdLoadStatus: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        switch self {
        case .done: return "done"
        case .error: return "error"
        case .inProgress: return "inProgress"
        case .none: return "none"
        @unknown default: return "unknown(\(self.rawValue))"
        }
    }
    
}

extension AdPresentation: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        switch self {
        case .willAppear: return "willAppear"
        case .didAppear: return "didAppear"
        case .willDisappear: return "willDisappear"
        case .didDisappear: return "didDisappear"
        case .didRewardUser: return "didRewardUser"
        case .errorInappropriateState: return "errorInappropriateState"
        case .errorNoAdsLoaded: return "errorNoAdsLoaded"
        case .errorFailedToPlay: return "errorFailedToPlay"
        case .errorCustomDataNotSet: return "errorCustomDataNotSet"
        @unknown default: return "unknown(\(self.rawValue))"
        }
    }
    
}

extension SKProduct {
    
    public override var debugDescription: String {
        return """
        SKProduct(identifier: \(productIdentifier), \
        localizedTitle: '\(localizedTitle)',
        price: \(price))
        """
    }
    
}
