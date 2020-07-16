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
import PsiApi
import PsiCashClient


extension RewardedVideoPresentation {
    
    init(objcAdPresentation: AdPresentation) {
        switch objcAdPresentation {
        case .willAppear:
            self = .willAppear
        case .didAppear:
            self = .didAppear
        case .willDisappear:
            self = .willDisappear
        case .didDisappear:
            self = .didDisappear
        case .didRewardUser:
            self = .didRewardUser
        case .errorInappropriateState:
            self = .errorInappropriateState
        case .errorNoAdsLoaded:
            self = .errorNoAdsLoaded
        case .errorFailedToPlay:
            self = .errorFailedToPlay
        case .errorCustomDataNotSet:
            self = .errorCustomDataNotSet
        @unknown default:
            fatalError("Unknown AdPresentation value: '\(objcAdPresentation)'")
        }
    }
    
}


extension RewardedVideoLoadStatus {
    
    init(objcAdLoadStatus: AdLoadStatus) {
        switch objcAdLoadStatus {
        case .none:
            self = .none
        case .inProgress:
            self = .inProgress
        case .done:
            self = .done
        case .error:
            self = .error
        @unknown default:
            fatalError("Unknown AdLoadStatus value: '\(objcAdLoadStatus)'")
        }
    }
    
}


extension PsiCashPurchaseResponseError: ErrorUserDescription {
    
    public var userDescription: String {
        switch self {
        case .tunnelNotConnected:
            return UserStrings.Psiphon_is_not_connected()
        case .parseError(_):
            return UserStrings.Operation_failed_alert_message()
        case let .serverError(psiCashStatus, _, _):
            switch PsiCashStatus(rawValue: psiCashStatus) {
            case .insufficientBalance:
                return UserStrings.Insufficient_psiCash_balance()
            default:
                return UserStrings.Operation_failed_alert_message()
            }
        }
    }
    
}


extension PsiCashStatus {
    
    /// Whether or not the request should be retried given the PsiCashStatus code.
    var shouldRetry: Bool {
        switch self {
        case .invalid, .serverError:
            return true
        case .success, .existingTransaction, .insufficientBalance, .transactionAmountMismatch,
             .transactionTypeNotFound, .invalidTokens:
            return false
        @unknown default:
            return false
        }
    }
    
}


extension PsiCashAmount: CustomStringFeedbackDescription {
    
    public var description: String {
        "PsiCash(inPsi %.2f: \(String(format: "%.2f", self.inPsi)))"
    }
    
}


extension PsiCashEffects {
    
    static func `default`(psiCash: PsiCash, feedbackLogger: FeedbackLogger) -> PsiCashEffects {
        PsiCashEffects(
            libData: { [psiCash] () -> PsiCashLibData in
                psiCash.dataModel()
            },
            refreshState: { [psiCash] (priceClasses, tunnelConnection) -> Effect<PsiCashRefreshResult> in
                Effect.deferred { fulfilled in
                    guard case .connected = tunnelConnection.tunneled else {
                        fulfilled(.completed(.failure(ErrorEvent(.tunnelNotConnected))))
                        return
                    }
                    
                    // Updates request metadata before sending the request.
                    psiCash.setRequestMetadata()
                    let purchaseClasses = priceClasses.map { $0.rawValue }
                    
                    psiCash.refreshState(purchaseClasses) { [fulfilled] psiCashStatus, error in
                        let result: Result<PsiCashLibData, ErrorEvent<PsiCashRefreshError>>
                        switch (psiCashStatus, error) {
                        case (.success, nil):
                            result = .success(psiCash.dataModel())
                        case (.serverError, nil):
                            result = .failure(ErrorEvent(.serverError))
                        case (.invalidTokens, nil):
                            result = .failure(ErrorEvent(.invalidTokens))
                        case (_, .some(let error)):
                            result = .failure(ErrorEvent(.error(SystemError(error))))
                        case (_, .none):
                            fatalError("unknown PsiCash status '\(psiCashStatus)'")
                        }
                        fulfilled(.completed(result))
                    }
                }
            },
            purchaseProduct: { [psiCash, feedbackLogger] (purchasable, tunnelConnection) -> Effect<PsiCashPurchaseResult> in
                Effect.deferred { fulfilled in
                    guard case .connected = tunnelConnection.tunneled else {
                        fulfilled(
                            PsiCashPurchaseResult(
                                purchasable: purchasable,
                                refreshedLibData: psiCash.dataModel(),
                                result: .failure(ErrorEvent(.tunnelNotConnected)))
                        )
                        return
                    }
                    
                    feedbackLogger.immediate(.info,
                                             "Purchase: '\(String(describing: purchasable))'")
                    
                    // Updates request metadata before sending the request.
                    psiCash.setRequestMetadata()
                    
                    psiCash.newExpiringPurchaseTransaction(
                        forClass: purchasable.rawTransactionClass,
                        withDistinguisher: purchasable.distinguisher,
                        withExpectedPrice: NSNumber(value: purchasable.price.inNanoPsi))
                    { (status: PsiCashStatus, purchase: PsiCashPurchase?, error: Error?) in
                        let result: PsiCashPurchaseResult
                        if status == .success, let purchase = purchase {
                            result = PsiCashPurchaseResult(
                                purchasable: purchasable,
                                refreshedLibData: psiCash.dataModel(),
                                result: purchase.mapToPurchased().mapError {
                                    ErrorEvent(PsiCashPurchaseResponseError.parseError($0))
                            })
                            
                        } else {
                            result = PsiCashPurchaseResult(
                                purchasable: purchasable,
                                refreshedLibData: psiCash.dataModel(),
                                result: .failure(ErrorEvent(
                                    .serverError(status: status.rawValue,
                                                 shouldRetry: status.shouldRetry,
                                                 error: error.map(SystemError.init))
                                ))
                            )
                        }
                        
                        fulfilled(result)
                    }
                }
            },
            modifyLandingPage: { [psiCash, feedbackLogger] url -> Effect<URL> in
                Effect { () -> URL in
                    var maybeModifiedURL: NSString?
                    let error = psiCash.modifyLandingPage(url.absoluteString,
                                                          modifiedURL: &maybeModifiedURL)
                    guard error == nil else {
                        feedbackLogger.immediate(.error,
                                                 "ModifyURLFailed: '\(String(describing: error))'")
                        feedbackLogger.immediate(.info,
                                                 "DiagnosticInfo: '\(psiCash.getDiagnosticInfo())'")
                        return url
                    }
                    
                    guard let modifiedURL = maybeModifiedURL else {
                        
                        feedbackLogger.immediate(.error, "ModifyURLFailed: modified URL is nil")
                        
                        feedbackLogger.immediate(.info,
                                                 "DiagnosticInfo: '\(psiCash.getDiagnosticInfo())'")
                        return url
                    }
                    
                    return URL(string: modifiedURL as String)!
                }
                
            },
            rewardedVideoCustomData: { [psiCash, feedbackLogger] () -> String? in
                var s: NSString?
                let error = psiCash.getRewardedActivityData(&s)
                
                guard error == nil else {
                    feedbackLogger.immediate(
                        .error,
                        "GetRewardedActivityDataFailed: '\(String(describing: error))'"
                    )
                    
                    feedbackLogger.immediate(.info,
                                             "DiagnosticInfo: '\(psiCash.getDiagnosticInfo())'")
                    return nil
                }
                
                return s as String?
        },
            expirePurchases: { [psiCash]
                (nonSubscriptionEncodedAuthorization: Set<String>) -> Effect<Never> in
                .fireAndForget {
                    let decoder = JSONDecoder.makeRfc3339Decoder()
                    
                    let nonSubscriptionAuthIDs = nonSubscriptionEncodedAuthorization
                        .compactMap { encodedAuth -> SignedAuthorization? in
                            guard let data = encodedAuth.data(using: .utf8) else {
                                return nil;
                            }
                            return try? decoder.decode(SignedAuthorization.self, from: data)
                    }.map(\.authorization.id)
                    
                    psiCash.expirePurchases(notFoundIn: nonSubscriptionAuthIDs)
                }
        }
        )
    }
    
}
