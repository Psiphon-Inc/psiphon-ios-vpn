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
import Promises
import ReactiveSwift

struct PurchaseVerifierServerEndpoints {

    private enum EndpointURL {
        case psiCash

        var url: URL {
            switch self {
            case .psiCash:
                if Debugging.devServers {
                    return URL(string: "https://dev-subscription.psiphon3.com/v2/appstore/psicash")!
                } else {
                    return URL(string: "https://subscription.psiphon3.com/v2/appstore/psicash")!
                }
            }
        }
    }

    static func psiCash(
        _ requestBody: PsiCashValidationRequest
    ) -> HTTPRequest<PsiCashValidationResponse>? {
        return HTTPRequest.json(url: EndpointURL.psiCash.url, body: requestBody,
                                clientMetaData: Current.clientMetaData.jsonString,
                                method: .post, response: PsiCashValidationResponse.self)
    }
}

struct PsiCashValidationRequest: Encodable {
    let productId: String
    let receiptData: String
    let customData: String
    
    init(transaction: UnverifiedPsiCashConsumableTransaction,
         receipt: Receipt,
         customData: CustomData) {
        self.productId = transaction.value.payment.productIdentifier
        self.receiptData = receipt.data.base64EncodedString()
        self.customData = customData
    }

    private enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case receiptData = "receipt-data"
        case customData = "custom_data"
    }
}

struct PsiCashValidationResponse: HTTPResponse {
    enum ResponseError: HashableError {
        case failedRequest(SystemError)
        case errorStatusCode(HTTPURLResponse)
    }

    let result: Result<(), ErrorEvent<ResponseError>>
    private let urlSessionResult: URLSessionResult

    init(urlSessionResult: URLSessionResult) {
        self.urlSessionResult = urlSessionResult

        // TODO: The mapping of types of `urlSessionResult` to `result` can be generalized.
        switch urlSessionResult {
        case let .success((_, urlResponse)):
            switch urlResponse.statusCode {
            case 200:
                self.result = .success(())
            default:
                self.result = .failure(ErrorEvent(.errorStatusCode(urlResponse)))
            }
        case let .failure(httpRequestError):
            self.result = .failure(httpRequestError.errorEvent.map { .failedRequest($0) })

        }
    }

    var shouldRetry: Bool {
        switch self.urlSessionResult {
        case .failure(_):
            return true
        case .success(let success):
            switch success.response.statusCode {
            case 500, 503: return true
            default: return false
            }
        }
    }
}

enum ConsumableVerificationError: HashableError {
    /// Wraps error produced during request building phase
    case requestBuildError(FatalError)
    /// Wraps error from purchase verifier server
    case serverError(PsiCashValidationResponse.ResponseError)
}

struct UnverifiedPsiCashConsumableTransaction: Equatable {
    let value: SKPaymentTransaction
}

struct VerifiedPsiCashConsumableTransaction: Equatable {
    let value: SKPaymentTransaction
}

/// Verifies provided `PsiCashConsumableTransaction` against purchase verifier server.
/// Returned effect completes only after successfully verifying the purchase.
/// If all retries to the purchase verifier server failed, it is next retried after a new tunneled event.
func verifyConsumable(
    _ transaction: UnverifiedPsiCashConsumableTransaction
) -> Effect<VerifiedPsiCashConsumableTransaction> {
    Current.vpnStatus.signalProducer
    .skipRepeats()
    .flatMap(.latest) { value
        -> SignalProducer<VerifiedPsiCashConsumableTransaction, Never> in
        let vpnStatus = Debugging.ignoreTunneledChecks ? .connected : value
        guard case .connected = vpnStatus else {
            return .never
        }
        return SignalProducer(value: Current.psiCashEffect.rewardedVideoCustomData())
            .flatMap(.latest) { maybeCustomData in
                guard let customData = maybeCustomData else {
                    return .init(error: .requestBuildError(
                        FatalError(message: "empty custom data")))
                }
                guard let receipt = Receipt.fromLocalReceipt(Current.appBundle) else {
                    return .init(error: .requestBuildError(
                        FatalError(message: "failed to read receipt")))
                }
                let maybeUrlRequest = PurchaseVerifierServerEndpoints.psiCash(
                    PsiCashValidationRequest(
                        transaction: transaction,
                        receipt: receipt,
                        customData: customData
                    )
                )
                guard let urlRequest = maybeUrlRequest else {
                    return .init(error: .requestBuildError(
                        FatalError(message: "failed to create url request")))
                }
                return httpRequest(request: urlRequest)
                    .flatMap(.latest, { (response: PsiCashValidationResponse) ->
                        SignalProducer<(), PsiCashValidationResponse.ResponseError> in
                        switch response.result {
                        case .success:
                            return .init(value: ())
                        case .failure(let errorEvent):
                            if response.shouldRetry {
                                return .init(error: errorEvent.error)
                            } else {
                                return .init(value: ())
                            }
                        }
                    })
                    .retry(upTo: 10, interval: 1.0, on: QueueScheduler.main)
                    .map(value: VerifiedPsiCashConsumableTransaction(value: transaction.value))
                    .mapError { .serverError($0) }
            }
            .on(failed: { (error: ConsumableVerificationError) in
                PsiFeedbackLogger.error(withType: "VerifyConsumable",
                                        message: "verification of consumable failed",
                                        object: error)
            }).flatMapError { _ -> Effect<VerifiedPsiCashConsumableTransaction> in
                return .never
            }
    }
    .take(first: 1)  // Since upstream signals do not complete, signal is terminated here.
}
