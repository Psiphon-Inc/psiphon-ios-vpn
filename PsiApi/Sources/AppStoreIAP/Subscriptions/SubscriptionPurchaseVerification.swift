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
import PsiApi

public struct SubscriptionValidationRequest: Codable {
    
    public let originalTransactionID: OriginalTransactionID
    public let webOrderLineItemID: WebOrderLineItemID
    public let productID: ProductID
    
    /// Base64 encoded string with padding.
    public let receiptData: String
    
    public init(
        originalTransactionID: OriginalTransactionID,
        webOrderLineItemID: WebOrderLineItemID,
        productID: ProductID,
        receipt: ReceiptData
    ) {
        self.originalTransactionID = originalTransactionID
        self.webOrderLineItemID = webOrderLineItemID
        self.productID = productID
        self.receiptData = receipt.data.base64EncodedString()
    }
    
    private enum CodingKeys: String, CodingKey {
        case originalTransactionID = "original_transaction_id"
        case webOrderLineItemID = "web_order_line_item_id"
        case productID = "product_id"
        case receiptData = "receipt_data"
    }
}


public struct SubscriptionValidationResponse: RetriableHTTPResponse {
    
    public enum ResponseError: HashableError {
        
        /// HTTP request failed.
        case failedRequest(SystemError<Int>)
        
        /// Received 400 Bad Request from purchse-verifier server.
        case badRequest
        
        /// Received 5xx server error.
        case serverError(HTTPStatusCode)
        
        /// Received unsupported/unknown status code.
        case unknownStatusCode(HTTPStatusCode)
        
        /// Failed to parse responsy body.
        case responseBodyParseError(SystemError<Int>)
    }
    
    // 200 OK response type
    public struct SuccessResult: Equatable, Codable {
        let requestDate: Date
        public let originalTransactionID: OriginalTransactionID
        public let webOrderLineItemID: WebOrderLineItemID
        public let signedAuthorization: PsiApi.SignedData<SignedAuthorization>?
        public let errorStatus: ErrorStatus
        public let errorDescription: String
        
        public enum ErrorStatus: Int, Codable, CaseIterable {
            case noError = 0
            case transactionExpired = 1
            // The transaction has been cancelled by Apple customer support
            case transactionCancelled = 2
        }
        
        private enum CodingKeys: String, CodingKey {
            case requestDate = "request_date"
            case originalTransactionID = "original_transaction_id"
            case webOrderLineItemID = "web_order_line_item_id"
            case signedAuthorization = "signed_authorization"
            case errorStatus = "error_status"
            case errorDescription = "error_description"
        }

        public init(
            requestDate: Date,
            originalTransactionID: OriginalTransactionID,
            webOrderLineItemID: WebOrderLineItemID,
            signedAuthorization: PsiApi.SignedData<SignedAuthorization>?,
            errorStatus: ErrorStatus,
            errorDescription: String
        ) {
            self.requestDate = requestDate
            self.originalTransactionID = originalTransactionID
            self.webOrderLineItemID = webOrderLineItemID
            self.signedAuthorization = signedAuthorization
            self.errorStatus = errorStatus
            self.errorDescription = errorDescription
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            requestDate = try values.decode(Date.self, forKey: .requestDate)
            originalTransactionID = try values.decode(OriginalTransactionID.self,
                                                      forKey: .originalTransactionID)
            webOrderLineItemID = try values.decode(WebOrderLineItemID.self,
                                                   forKey: .webOrderLineItemID)
            errorStatus = try values.decode(ErrorStatus.self, forKey: .errorStatus)
            errorDescription = try values.decode(String.self, forKey: .errorDescription)
            
            switch errorStatus {
            case .noError:
                let base64Auth = try values.decode(String.self, forKey: .signedAuthorization)
                guard let base64Data = Data(base64Encoded: base64Auth) else {
                    fatalError(
                        "Failed to create data from base64 encoded string: '\(base64Auth)'"
                    )
                }
                let decoder = JSONDecoder.makeRfc3339Decoder()
                let decodedAuth = try decoder.decode(SignedAuthorization.self, from: base64Data)
                signedAuthorization = SignedData(rawData: base64Auth, decoded: decodedAuth)
            default:
                signedAuthorization = nil
            }
        }
    }

    public let result: Result<SuccessResult, ErrorEvent<ResponseError>>
    private let urlSessionResult: URLSessionResult

    public init(urlSessionResult: URLSessionResult) {
        self.urlSessionResult = urlSessionResult

        // TODO: The mapping of types of `urlSessionResult` to `result` can be generalized.
        switch urlSessionResult.result {
        case let .success(r):
            switch r.metadata.statusCode {
            case .ok:
                do {
                    let decoder = JSONDecoder.makeRfc3339Decoder()
                    let decodedBody = try decoder.decode(SuccessResult.self, from: r.data)
                    self.result = .success(decodedBody)
                } catch {
                    self.result = .failure(ErrorEvent(.responseBodyParseError(SystemError<Int>.make(error as NSError)),
                                                      date: urlSessionResult.date))
                }
            case .badRequest:
                self.result = .failure(ErrorEvent(.badRequest, date: urlSessionResult.date))
            
            default:
                // If the status code is not 200 OK or 400 Bad Request Error,
                // it is either a 5xx server error, or an uknown/unsupported status code.
                if case .serverError = r.metadata.statusCode.responseType {
                    self.result = .failure(ErrorEvent(.serverError(r.metadata.statusCode),
                                                      date: urlSessionResult.date))
                } else {
                    self.result = .failure(ErrorEvent(.unknownStatusCode(r.metadata.statusCode),
                                                      date: urlSessionResult.date))
                }
            }
        case let .failure(httpRequestError):
            self.result = .failure(ErrorEvent(.failedRequest(httpRequestError.error),
                                              date: urlSessionResult.date))
        }
    }

    public static func unpackRetriableResultError(_ result: ResultType)
        -> (result: ResultType, retryDueToError: FailureEvent?)
    {
        switch result {
        case .success(_):
            return (result: result, retryDueToError: .none)
            
        case .failure(let errorEvent):
            
            // Request is automatically retried if network failed, there was a 5xx server error,
            // parsing of the respose body failed (probably network failure).
            switch errorEvent.error {
            case .failedRequest(_),
                    .responseBodyParseError(_),
                    .serverError(_):
                return (result: result, retryDueToError: errorEvent)
                
            case .badRequest, .unknownStatusCode(_):
                return (result: result, retryDueToError: .none)
            }
        }
    }

}
