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
import SwiftCheck
@testable import AppStoreIAP

enum GenSubscriptionStatus : CaseIterable {
    case subscribed
    case notSubscribed
    case unknown
}

extension GenSubscriptionStatus: Arbitrary {
    public static var arbitrary: Gen<GenSubscriptionStatus> {
        Gen.fromElements(of: GenSubscriptionStatus.allCases)
    }
}

extension SubscriptionStatus : Arbitrary {
    public static var arbitrary: Gen<SubscriptionStatus> {
        GenSubscriptionStatus.arbitrary.flatMap { n -> Gen<SubscriptionStatus> in
            switch n {
            case .subscribed:
                return SubscriptionIAPPurchase.arbitrary.map(SubscriptionStatus.subscribed)
            case .notSubscribed:
                return Gen.pure(.notSubscribed)
            case .unknown:
                return Gen.pure(.unknown)
            }
        }
    }
}

enum GenSubscriptionActions : CaseIterable {
    case updatedReceiptData
    case timerFinished
}

extension GenSubscriptionActions: Arbitrary {
    public static var arbitrary: Gen<GenSubscriptionActions> {
        Gen.fromElements(of: GenSubscriptionActions.allCases)
    }
}

extension SubscriptionAction: Arbitrary {
    public static var arbitrary: Gen<SubscriptionAction> {

        GenSubscriptionActions.arbitrary.flatMap { n -> Gen<SubscriptionAction> in

            switch n {
            case .updatedReceiptData:
                return ReceiptData?.arbitrary.map(SubscriptionAction.updatedReceiptData)

            case .timerFinished:
                return Date.arbitrary.flatMap { date -> Gen<SubscriptionAction> in
                    Gen.pure(._timerFinished(withExpiry: date))
                }
            }
        }
    }
}
