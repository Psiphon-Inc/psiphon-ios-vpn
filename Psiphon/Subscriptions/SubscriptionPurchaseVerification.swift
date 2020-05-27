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
import AppStoreIAP

struct SubscriptionValidationRequest: Encodable {
    let originalTransactionID: OriginalTransactionID
    let receiptData: String
    
    init(originalTransactionID: OriginalTransactionID, receipt: ReceiptData) {
        self.originalTransactionID = originalTransactionID
        self.receiptData = receipt.data.base64EncodedString()
    }
    
    private enum CodingKeys: String, CodingKey {
        case originalTransactionID = "original_transaction_id"
        case receiptData = "receipt_data"
    }
}


struct SubscriptionValidationResponse: RetriableHTTPResponse {
    
    enum ResponseError: HashableError {
        case failedRequest(SystemError)
        case badRequest
        case otherErrorStatusCode(HTTPStatusCode)
        case responseParseError(SystemError)
    }
    
    // 200 OK response type
    struct SuccessResult: Equatable, Decodable {
        let requestDate: Date
        let originalTransactionID: OriginalTransactionID
        let signedAuthorization: PsiApi.SignedData<SignedAuthorization>?
        let errorStatus: ErrorStatus
        let errorDescription: String
        
        enum ErrorStatus: Int, Decodable {
            case noError = 0
            case transactionExpired = 1
            // The transaction has been cancelled by Apple customer support
            case transactionCancelled = 2
        }
        
        private enum CodingKeys: String, CodingKey {
            case requestDate = "request_date"
            case originalTransactionID = "original_transaction_id"
            case signedAuthorization = "signed_authorization"
            case errorStatus = "error_status"
            case errorDescription = "error_description"
        }
        
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            requestDate = try values.decode(Date.self, forKey: .requestDate)
            originalTransactionID = try values.decode(OriginalTransactionID.self,
                                                      forKey: .originalTransactionID)
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

    let result: Result<SuccessResult, ErrorEvent<ResponseError>>
    private let urlSessionResult: URLSessionResult

    init(urlSessionResult: URLSessionResult) {
        self.urlSessionResult = urlSessionResult

        // TODO: The mapping of types of `urlSessionResult` to `result` can be generalized.
        switch urlSessionResult {
        case let .success((data, urlResponse)):
            switch urlResponse.typedStatusCode {
            case .ok:
                do {
                    let decoder = JSONDecoder.makeRfc3339Decoder()
                    let decodedBody = try decoder.decode(SuccessResult.self, from: data)
                    self.result = .success(decodedBody)
                } catch {
                    self.result = .failure(ErrorEvent(.responseParseError(error as SystemError)))
                }
            case .badRequest:
                self.result = .failure(ErrorEvent(.badRequest))
            default:
                self.result = .failure(ErrorEvent(
                    .otherErrorStatusCode(urlResponse.typedStatusCode)))
            }
        case let .failure(httpRequestError):
            self.result = .failure(httpRequestError.errorEvent.map { .failedRequest($0) })

        }
    }

    static func unpackRetriableResultError(_ result: ResultType)
        -> (result: ResultType, retryDueToError: FailureEvent?)
    {
        switch result {
        case .success(_):
            return (result: result, retryDueToError: .none)
            
        case .failure(let errorEvent):
            switch errorEvent.error {
            case .otherErrorStatusCode(.internalServerError),
                 .otherErrorStatusCode(.serviceUnavailable),
                 .failedRequest(_),
                 .responseParseError(_):
                return (result: result, retryDueToError: errorEvent)
                
            case .badRequest,
                 .otherErrorStatusCode:
                return (result: result, retryDueToError: .none)
            }
        }
    }

}
