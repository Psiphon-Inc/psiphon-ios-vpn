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

extension SubscriptionIAPPurchase: Arbitrary {
    public static var arbitrary: Gen<SubscriptionIAPPurchase> {
        Gen.compose { c in
            return SubscriptionIAPPurchase(
                productID: c.generate(),
                transactionID: c.generate(),
                originalTransactionID: c.generate(),
                purchaseDate: c.generate(),
                expires: c.generate(),
                isInIntroOfferPeriod: c.generate(),
                hasBeenInIntroOfferPeriod: c.generate())
        }
    }
}

extension ConsumableIAPPurchase: Arbitrary {
    public static var arbitrary: Gen<ConsumableIAPPurchase> {
        Gen.compose { c in
            ConsumableIAPPurchase(productID: c.generate(), transactionID: c.generate())
        }
    }
}

extension ReceiptData: Arbitrary {
    public static var arbitrary: Gen<ReceiptData> {
        Gen.compose { c in
            ReceiptData(subscriptionInAppPurchases: c.generate(),
                        consumableInAppPurchases: c.generate(),
                        data: Data(), // TODO: currently unused in testing
                        readDate: c.generate())
        }
    }
}

extension ReceiptReadReason: Arbitrary {
    public static var arbitrary: Gen<ReceiptReadReason> {
        Gen<ReceiptReadReason>.fromElements(of: ReceiptReadReason.allCases)
    }
}

// Mirror of function of the same name in `SubscriptionIAPPurchase` for testing.
func isApproximatelyExpired(date: Date) -> Bool {
    switch compareDates(Date(), to: date) {
        case .orderedAscending: return false
        case .orderedDescending: return true
        case .orderedSame: return true
    }
}

func compareDates(_ date1: Date, to date2: Date) -> ComparisonResult {
    return Calendar.current.compare(date1,
                                    to: date2,
                                    toGranularity: .second)
}
