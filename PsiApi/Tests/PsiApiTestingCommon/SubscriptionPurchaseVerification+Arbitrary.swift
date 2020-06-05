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

extension HTTPResponseData {

    static func arbitraryPurchaseVerificationResponse() -> Gen<HTTPResponseData> {

        Gen.compose { c in
            // Generate a random request response
            let result: SubscriptionValidationResponse.SuccessResult? = c.generate()
            let encoder = JSONEncoder.makeRfc3339Encoder()
            let data = try! encoder.encode(result)

            let metadata: HTTPResponseMetadata =
                c.generate(using:
                    HTTPResponseMetadata.arbitraryPurchaseVerificationMetadata())

            return HTTPResponseData(data: data,
                                    metadata: metadata)
        }
    }

    static func arbitraryPurchaseVerificationResponse(req: URLRequest) -> Gen<HTTPResponseData> {

        Gen.compose { c in

            var data: Data = Data()

            if let requestData = req.httpBody {

                // Generate a random request response
                let result: SubscriptionValidationResponse.SuccessResult? = c.generate()

                if let reifiedResult = result {

                    // If a response will be returned:
                    // - Overwrite the random transaction ID with the one in the request
                    // - Make the authorization value in the response JSON a base64 encoded
                    //   string (this is what the decoder expects)

                    let decoder = JSONDecoder.makeRfc3339Decoder()
                    let decodedRequest = try! decoder.decode(SubscriptionValidationRequest.self, from: requestData)

                    let encoder = JSONEncoder.makeRfc3339Encoder()
                    let firstEncoding = try! encoder.encode(reifiedResult)

                    var response: [String: Any] = try! JSONSerialization.jsonObject(with: firstEncoding, options: []) as! [String : Any]

                    if case .noError = reifiedResult.errorStatus {
                        // A signed authorization is expected if there was no error.

                        var base64EncodedAuthorization = ""
                        if let rawData = reifiedResult.signedAuthorization?.rawData {
                            base64EncodedAuthorization = rawData
                        } else {
                            let signedAuth : PsiApi.SignedData<SignedAuthorization> = c.generate()
                            base64EncodedAuthorization = signedAuth.rawData
                        }
                        response["authorization"] = base64EncodedAuthorization
                        response["original_transaction_id"] = String(describing: decodedRequest.originalTransactionID)
                    }

                    data = try! JSONSerialization.data(withJSONObject: response)
                }
            }

            let metadata: HTTPResponseMetadata =
                c.generate(using:
                    HTTPResponseMetadata.arbitraryPurchaseVerificationMetadata())

            return HTTPResponseData(data: data,
                                    metadata: metadata)
        }
    }
}

extension HTTPResponseMetadata {
    fileprivate static func arbitraryPurchaseVerificationMetadata() -> Gen<HTTPResponseMetadata> {
        Gen.compose { c in
            // Bias status codes that are expected.
            let statusCodeGen: Gen<HTTPStatusCode> =
                Gen.one(of: [
                    Gen.fromElements(of: [200, 400, 500]).map {
                        HTTPStatusCode(rawValue: $0)!
                    },
                    HTTPStatusCode.arbitrary
                ])

            // Note: url unused in testing thus far.
            return HTTPResponseMetadata(url: URL(string:"https://example.com")!,
                                        headers: [:],
                                        statusCode: c.generate(using: statusCodeGen))
        }
    }
}


extension HTTPClient {
    public static func arbitraryPurchaseVerificationClient() -> Gen<HTTPClient> {
        HTTPClient.arbitrary(resultGen: { urlRequest in
            Gen.frequency([
                (3,
                 HTTPResponseData.arbitraryPurchaseVerificationResponse(req: urlRequest).map(Result.success)),
                (1,
                 HTTPRequestError.arbitrary.map(Result.failure))
            ])
        })
    }
}

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
