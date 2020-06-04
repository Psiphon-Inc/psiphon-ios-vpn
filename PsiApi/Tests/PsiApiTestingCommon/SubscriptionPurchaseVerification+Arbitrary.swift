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
@testable import PsiApi
@testable import AppStoreIAP

extension SubscriptionValidationResponse.ResponseError: Arbitrary {
    public static var arbitrary: Gen<SubscriptionValidationResponse.ResponseError> {
        Gen.one(of: [
            // All cases should be covered.
            SystemError.arbitrary.map(
                SubscriptionValidationResponse.ResponseError.failedRequest
            ),
            Gen.pure(SubscriptionValidationResponse.ResponseError.badRequest),
            HTTPStatusCode.arbitrary.map(
                SubscriptionValidationResponse.ResponseError.otherErrorStatusCode
            ),
            SystemError.arbitrary.map(
                SubscriptionValidationResponse.ResponseError.responseParseError
            )
        ])
    }
}

extension SubscriptionValidationResponse.SuccessResult: Arbitrary {
    public static var arbitrary: Gen<SubscriptionValidationResponse.SuccessResult> {
        Gen.compose { c in
            SubscriptionValidationResponse.SuccessResult(
                requestDate: c.generate(),
                originalTransactionID: c.generate(),
                signedAuthorization: c.generate(),
                errorStatus: c.generate(),
                errorDescription: c.generate())
        }
    }
}

extension SubscriptionValidationResponse.SuccessResult.ErrorStatus: Arbitrary {
    public static var arbitrary: Gen<SubscriptionValidationResponse.SuccessResult.ErrorStatus> {
        Gen<SubscriptionValidationResponse.SuccessResult.ErrorStatus>.fromElements(of:
            SubscriptionValidationResponse.SuccessResult.ErrorStatus.allCases)
    }
}
