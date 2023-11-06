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
import Utilities
import PsiApi
import PsiCashClient

public struct PsiCashValidationRequest: Encodable {
    let productID: ProductID
    let transactionID: TransactionID
    let receiptData: String
    let customData: String
    
    public init(
        productID: ProductID,
        transactionID: TransactionID,
        receipt: ReceiptData,
        customData: CustomData
    ) {
        self.productID = productID
        self.transactionID = transactionID
        self.receiptData = receipt.data.base64EncodedString()
        self.customData = customData
    }

    private enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case transactionID = "transaction_id"
        case receiptData = "receipt-data"
        case customData = "custom_data"
    }
}

public struct PsiCashValidationResponse: RetriableHTTPResponse {
    
    public enum ResponseError: HashableError {
        /// Request utterly failed.
        case failedRequest(SystemError<Int>)
        /// Received a non-2xx HTTP response.
        case errorStatusCode(HTTPResponseMetadata)
    }

    public let result: Result<Utilities.Unit, ErrorEvent<ResponseError>>
    
    init(result: Result<Utilities.Unit, ErrorEvent<ResponseError>>) {
        self.result = result
    }

    public init(urlSessionResult: URLSessionResult) {
        switch urlSessionResult.result {
        case let .success(r):
            switch r.metadata.respStatus {
            case .ok:
                self.result = .success(.unit)
            default:
                self.result = .failure(ErrorEvent(.errorStatusCode(r.metadata),
                                                  date: urlSessionResult.date))
            }
        case let .failure(httpRequestError):
            self.result = .failure(ErrorEvent(.failedRequest(httpRequestError.error),
                                              date: urlSessionResult.date))

        }   
    }
    
    public static func unpackRetriableResultError(
        _ result: ResultType
    ) -> (result: ResultType, retryDueToError: FailureEvent?) {
        switch result {
            
        // Request succeeded.
        case .success(.unit):
            return (result: result, retryDueToError: .none)
            
        // Request failed.
        case .failure(let errorEvent):
            switch errorEvent.error {
            
            case .failedRequest(_):
                // Retry if the request failed due to networking or reasons
                // unrelated to a response from the server.
                return (result: result, retryDueToError: errorEvent)
                
            case .errorStatusCode(let metadata):
                // Received a non-200 OK response from the server.
                switch metadata.respStatus {
                case .internalServerError,
                     .serviceUnavailable:
                    // Retry if the HTTP status code is 500 or 503.
                    return (result: result, retryDueToError: errorEvent)
                    
                default:
                    // Do not retry otherwise.
                    return (result: result, retryDueToError: .none)
                }
            }
        }
    }
}

public enum ConsumableVerificationError: HashableError {
    /// Wraps error produced during request building phase
    case requestBuildError(FatalError)
    /// Wraps error from purchase verifier server
    case serverError(PsiCashValidationResponse.ResponseError)
}
