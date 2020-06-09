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
import ReactiveSwift
import PsiCashClient
import Testing
import StoreKit
import SwiftCheck
import Utilities
@testable import PsiApi
@testable import AppStoreIAP

func returnGeneratedOrFail<A>(_ gen: Gen<A>?) -> A {
    // TODO: Calling generate hinders replay functionality.
    guard let generated = gen?.generate else {
        XCTFatal()
    }
    return generated
}

func positiveDouble() -> Gen<Double> {
    Double.arbitrary.map(abs)
}

extension Utilities.Unit: Arbitrary {
    public static var arbitrary: Gen<Utilities.Unit> {
        Gen.pure(.unit)
    }
}

extension Pair: Arbitrary where A: Arbitrary, B: Arbitrary {
    public static var arbitrary: Gen<Pair<A, B>> {
        Gen.zip(A.arbitrary, B.arbitrary).map(Pair.init)
    }
}

extension Date: Arbitrary {
    /// Arbitrary date roughly in the range 1970s to 2096 with digits up to six decimal places.
    public static var arbitrary: Gen<Date> {
        Int64.arbitrary.resize(3_999_999_999_999_999).map { microSecondsUnix in
             Date(timeIntervalSince1970: Double(abs(microSecondsUnix)) / 1_000_000.0)
        }
    }
}

extension SKError: Arbitrary {
    public static var arbitrary: Gen<SKError> {
        Gen.fromElements(in: 0...14).map { code -> SKError in
            SKError(_nsError: NSError(domain: SKError.errorDomain,
                                      code: code,
                                      userInfo: nil))
        }
    }
}

extension Result: Arbitrary where Success: Arbitrary, Failure: Arbitrary {
    public static var arbitrary: Gen<Result<Success, Failure>> {
        Gen.one(of: [
            Success.arbitrary.map(Result.success),
            Failure.arbitrary.map(Result.failure),
        ])
    }
}

extension ErrorRepr: Arbitrary {
    public static var arbitrary: Gen<ErrorRepr> {
        String.arbitrary.map(ErrorRepr.init(repr:))
    }
}

extension ErrorEvent: Arbitrary where E: Arbitrary {
    public static var arbitrary: Gen<ErrorEvent<E>> {
        Gen.zip(E.arbitrary, Date.arbitrary).map(ErrorEvent.init(_: date:))
    }
}

extension SystemError: Arbitrary {
    public static var arbitrary: Gen<SystemError> {
        Gen.compose { c in
            SystemError(domain: c.generate(),
                        code: c.generate())
        }
    }
}

extension Locale: Arbitrary {
    public static var arbitrary: Gen<Locale> {
        Gen.fromElements(of: Locale.availableIdentifiers).map(Locale.init(identifier:))
    }
}

extension Pending: Arbitrary where Completed: Arbitrary {
    public static var arbitrary: Gen<Pending<Completed>> {
        Gen.frequency([
            (1, Gen.pure(.pending)),
            (4, Completed.arbitrary.map(Pending.completed))
        ])
    }
}

extension PendingValue: Arbitrary where Pending: Arbitrary, Completed: Arbitrary {
    public static var arbitrary: Gen<PendingValue<Pending, Completed>> {
        Gen.frequency([
            (1, Pending.arbitrary.map(PendingValue.pending)),
            (3, Completed.arbitrary.map(PendingValue.completed))
        ])
    }
    
    /// Generates arbitrary `PendingValue.completed` values.
    static var arbitraryWithOnlyCompleted: Gen<PendingValue<Pending, Completed>> {
        Completed.arbitrary.map(PendingValue.completed)
    }
}

extension OrderedSet: Arbitrary where E: Arbitrary {
    public static var arbitrary: Gen<OrderedSet<E>> {
        [E].arbitrary.map(OrderedSet.init)
    }
}
