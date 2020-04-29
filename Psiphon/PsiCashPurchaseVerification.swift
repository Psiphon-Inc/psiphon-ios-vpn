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

struct PsiCashValidationRequest: Encodable {
    let productId: String
    let receiptData: String
    let customData: String
    
    init(transaction: UnverifiedPsiCashConsumableTransaction,
         receipt: ReceiptData,
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

    let result: Result<Unit, ErrorEvent<ResponseError>>
    private let urlSessionResult: URLSessionResult

    init(urlSessionResult: URLSessionResult) {
        self.urlSessionResult = urlSessionResult

        // TODO: The mapping of types of `urlSessionResult` to `result` can be generalized.
        switch urlSessionResult {
        case let .success((_, urlResponse)):
            switch urlResponse.statusCode {
            case 200:
                self.result = .success(.unit)
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

extension UnverifiedPsiCashConsumableTransaction {
    
    /// Compares transaction identifier to provided `transaction`'s transaction identifier.
    /// - Returns: true if both transaction id are non-nil and are equal, false otherwise.
    func isEqualTransactionId(to transaction: SKPaymentTransaction) -> Bool {
        guard let idA = value.transactionIdentifier else {
            return false
        }
        guard let idB = transaction.transactionIdentifier else {
            return false
        }
        return idA == idB
    }
}

struct VerifiedPsiCashConsumableTransaction: Equatable {
    let value: SKPaymentTransaction
}

/// Verifies provided `PsiCashConsumableTransaction` against purchase verifier server.
/// Returned effect completes only after successfully verifying the purchase.
/// If all retries to the purchase verifier server failed, it is next retried after a new tunneled event.
// TODO: Use RetriableTunneledHttpRequest
func verifyConsumable(
    transaction: UnverifiedPsiCashConsumableTransaction,
    receipt: ReceiptData,
    tunnelProviderStatusSignal: SignalProducer<VPNStatusWithIntent, Never>,
    psiCashEffects: PsiCashEffect,
    clientMetaData: ClientMetaData
) -> Effect<VerifiedPsiCashConsumableTransaction> {
    tunnelProviderStatusSignal
        .skipRepeats()
        .flatMap(.latest) { value -> Effect<VerifiedPsiCashConsumableTransaction> in
            let vpnStatus = Debugging.ignoreTunneledChecks ? .connected : value.status
            guard case .connected = vpnStatus else {
                return .never
            }
            return SignalProducer(value: psiCashEffects.rewardedVideoCustomData())
                .flatMap(.latest) { maybeCustomData in
                    guard let customData = maybeCustomData else {
                        return .init(error: .requestBuildError(
                            FatalError(message: "empty custom data")))
                    }
                    
                    let request = PurchaseVerifierServerEndpoints.psiCash(
                        requestBody: PsiCashValidationRequest(
                            transaction: transaction,
                            receipt: receipt,
                            customData: customData
                        ),
                        clientMetaData: clientMetaData
                    )
                    
                    return httpRequest(request: request)
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
