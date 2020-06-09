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

func httpVersionGen() -> Gen<String> {
    Gen.fromElements(of: ["HTTP/1.1", "HTTP/2"])
}

extension HTTPStatusCode: Arbitrary {
    public static var arbitrary: Gen<HTTPStatusCode> {
        Gen.fromElements(of: HTTPStatusCode.allCases)
    }
}

extension HttpRequestTunnelError: Arbitrary {
    public static var arbitrary: Gen<HttpRequestTunnelError> {
        Gen.fromElements(of: HttpRequestTunnelError.allCases)
    }
}

extension HTTPResponseMetadata: Arbitrary {
    public static var arbitrary: Gen<HTTPResponseMetadata> {
        Gen.compose { c in
            HTTPResponseMetadata(url: URL(string: "https://psiphon.ca")!,
                                 headers: [String: String](),
                                 statusCode: c.generate())
        }
    }
}

extension RetriableTunneledHttpRequest.RequestResult.RetryCondition: Arbitrary where
Response.Success: Arbitrary, Response.Failure: Arbitrary {
    public static var arbitrary: Gen<RetriableTunneledHttpRequest<Response>.RequestResult.RetryCondition> {
        Gen.one(of: [
            // Should cover all cases
            HttpRequestTunnelError.arbitrary
                .map(RetriableTunneledHttpRequest.RequestResult.RetryCondition
                    .whenResolved(tunnelError:)),
            
            Gen.zip(Gen.pure(DispatchTimeInterval.seconds(0)),
                    Response.ResultType.arbitrary)
                .map(RetriableTunneledHttpRequest.RequestResult.RetryCondition
                    .afterTimeInterval(interval: result:))
        ])
    }
}

extension RetriableTunneledHttpRequest.RequestResult: Arbitrary where
Response.Success: Arbitrary, Response.Failure: Arbitrary {
    public static var arbitrary: Gen<RetriableTunneledHttpRequest<Response>.RequestResult> {
        Gen.one(of: [
            // Should cover all cases
            RetryCondition.arbitrary.map(RetriableTunneledHttpRequest.RequestResult.willRetry),
            
            ErrorEvent<Response.Failure>.arbitrary
                .map(RetriableTunneledHttpRequest.RequestResult.failed),

            Response.ResultType.arbitrary.map(RetriableTunneledHttpRequest.RequestResult.completed)
        ])
    }
}
