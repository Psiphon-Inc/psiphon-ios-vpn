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


extension PsiCashPurchaseResponseError: LocalizedUserDescription {
    
    public var localizedUserDescription: String {
        switch self {
        case .tunnelNotConnected:
            return UserStrings.Psiphon_is_not_connected()
        case .requestFailed(message: _):
            return UserStrings.Operation_failed_please_try_again_alert_message()
        case let .purchaseFailed(psiStatus: psiStatus, shouldRetry: _):
            switch PSIStatus(rawValue: psiStatus) {
            case .insufficientBalance:
                return UserStrings.Insufficient_psiCash_balance()
            default:
                return UserStrings.Operation_failed_please_try_again_alert_message()
            }
        }
    }
    
}


extension PSIStatus {
    
    /// Whether or not the request should be retried given the PsiCashStatus code.
    var shouldRetry: Bool {
        switch self {
        case .invalid, .serverError:
            return true
        case .success, .existingTransaction, .insufficientBalance, .transactionAmountMismatch,
             .transactionTypeNotFound, .invalidTokens, .invalidCredentials, .badRequest:
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


fileprivate struct PsiCashHTTPResponse: HTTPResponse {
    typealias Success = PSIHttpResult
    typealias Failure = Never
    
    var result: ResultType
    
    var psiHTTPResult: PSIHttpResult {
        result.successToOptional()!
    }
    
    init(urlSessionResult: URLSessionResult) {
        switch urlSessionResult {
        case let .success(r):
            
            let statusCode = Int32(r.metadata.statusCode.rawValue)
            
            guard let body = String(data: r.data, encoding: .utf8) else {
                result = .success(PSIHttpResult(criticalError: ()))
                return
            }
            
            guard let date = r.metadata.headers[HTTPDateHeader.headerKey] else {
                result = .success(PSIHttpResult(criticalError: ()))
                return
            }
            
            result = .success(PSIHttpResult(code: statusCode, body: body, date: date, error: ""))
            
        case let .failure(httpRequestError):
            if let partialResponse = httpRequestError.partialResponseMetadata {
                let statusCode = Int32(partialResponse.statusCode.rawValue)
                let date = partialResponse.headers[HTTPDateHeader.headerKey] ?? ""
                result = .success(PSIHttpResult(code: statusCode, body: "", date: date,
                                                error: httpRequestError.localizedDescription))
            } else {
                result = .success(PSIHttpResult(code: PSIHttpResult.recoverable_ERROR(),
                                                body: "", date: "",
                                                error: httpRequestError.localizedDescription))
            }
        }
    }
    
}


extension PsiCashEffects {
    
    static func `default`(
        psiCash: PsiCash,
        httpClient: HTTPClient,
        globalDispatcher: GlobalDispatcher,
        getCurrentTime: @escaping () -> Date,
        feedbackLogger: FeedbackLogger
    ) -> PsiCashEffects {
        PsiCashEffects(
            initialize: { [psiCash] (fileStoreRoot: String?)
                -> Effect<Result<PsiCashLibData, ErrorRepr>> in
                
                guard let fileStoreRoot = fileStoreRoot else {
                    return Effect(value: .failure(ErrorRepr(repr: "nil psicash file store root")))
                }
                
                let maybeError = psiCash.initialize(
                    userAgent: PsiCashClientHardCodedValues.userAgent,
                    fileStoreRoot: fileStoreRoot,
                    httpRequestFunc: { (request: PSIHttpRequest) -> PSIHttpResult in
                        
                        // Maps [PSIPair<NSString>] to Swift type `[(String, String)]`.
                        let queryParams: [(String, String)] = request.query.map {
                            ($0.first as String, $0.second as String)
                        }
                        
                        guard let httpMethod = HTTPMethod(rawValue: request.method) else {
                            return PSIHttpResult(criticalError: ())
                        }
                        
                        let maybeUrl = URL.make(scheme: request.scheme, hostname: request.hostname,
                                                port: request.port, path: request.path,
                                                queryParams: queryParams)
                        
                        guard let url = maybeUrl else {
                            return PSIHttpResult(criticalError: ())
                        }
                        
                        let httpRequest = HTTPRequest(url: url,
                                                      httpMethod: httpMethod,
                                                      headers: request.headers,
                                                      body: request.body.data(using: .utf8),
                                                      response: PsiCashHTTPResponse.self)
                        
                        
                        // Makes async HTTPClient call into a sync call.
                        let sem = DispatchSemaphore(value: 0)
                        
                        var response: PsiCashHTTPResponse? = nil
                        
                        // Ignores `CancellableURLRequest` return value, as PsiCash
                        // requests are never cancelled.
                        let _ = httpClient.request(getCurrentTime, httpRequest) {
                            response = $0
                            sem.signal()
                        }
                        sem.wait()
                        
                        return response!.psiHTTPResult
                    },
                    test: Debugging.devServers)
                
                switch maybeError {
                case .none:
                    return Effect(value: .success(psiCash.dataModel))
                case .some(let error):
                    return Effect(value: .failure(ErrorRepr(repr: String(describing: error))))
                }
            } ,
            libData: { [psiCash] () -> PsiCashLibData in
                psiCash.dataModel
            },
            refreshState: { [psiCash] (priceClasses, tunnelConnection, metadata) ->
                Effect<PsiCashRefreshResult> in
                Effect.deferred(dispatcher: globalDispatcher) { fulfilled in
                    guard case .connected = tunnelConnection.tunneled else {
                        fulfilled(.completed(.failure(ErrorEvent(.tunnelNotConnected))))
                        return
                    }
                    
                    // Updates request metadata before sending the request.
                    let maybeError = psiCash.setRequestMetadata(metadata)
                    guard maybeError == nil else {
                        feedbackLogger.fatalError("failed to set request metadata")
                        return
                    }
                    
                    let purchaseClasses = priceClasses.map(\.rawValue)
    
                    // Blocking call.
                    let result = psiCash.refreshState(purchaseClasses: purchaseClasses)
                    
                    let mappedResult: Result<PsiCashLibData, ErrorEvent<PsiCashRefreshError>> =
                        result.biFlatMap({ psiStatus in
                            switch psiStatus {
                            case .success:
                                return .success(psiCash.dataModel)
                            case .serverError:
                                return .failure(ErrorEvent(.serverError))
                            case .invalidTokens:
                                return .failure(ErrorEvent(.invalidTokens))
                            default:
                                return .failure(
                                    ErrorEvent(.error("unexpected status '\(psiStatus)'")))
                            }
                        }, { failure in
                            return .failure(ErrorEvent(.error(failure.description)))
                        })
                    
                    fulfilled(.completed(mappedResult))
                }
            },
            purchaseProduct: { [psiCash, feedbackLogger] (purchasable, tunnelConnection, metadata) ->
                Effect<PsiCashPurchaseResult> in
                
                Effect.deferred(dispatcher: globalDispatcher) { fulfilled in
                    guard case .connected = tunnelConnection.tunneled else {
                        fulfilled(
                            PsiCashPurchaseResult(
                                purchasable: purchasable,
                                refreshedLibData: psiCash.dataModel,
                                result: .failure(ErrorEvent(.tunnelNotConnected)))
                        )
                        return
                    }
                    
                    feedbackLogger.immediate(.info,
                                             "Purchase: '\(String(describing: purchasable))'")
                    
                    // Updates request metadata before sending the request.
                    let maybeError = psiCash.setRequestMetadata(metadata)
                    guard maybeError == nil else {
                        feedbackLogger.fatalError("failed to set request metadata")
                        return
                    }
                    
                    // Blocking call.
                    let result = psiCash.newExpiringPurchase(
                        transactionClass: purchasable.rawTransactionClass,
                        distinguisher: purchasable.distinguisher,
                        expectedPrice: purchasable.price)
                    
                    let mappedResult:
                        Result<Result<PsiCashPurchasedType, PsiCashParseError>, ErrorEvent<PsiCashPurchaseResponseError>> =
                        result.biFlatMap({ (response: PsiCash.NewExpiringPurchaseResponse) in
                            if case .success = response.status,
                               let purchaseResult = response.purchaseResult {
                                return .success(purchaseResult)
                            } else {
                                return .failure(
                                    ErrorEvent(.purchaseFailed(
                                                psiStatus: response.status.rawValue,
                                                shouldRetry: response.status.shouldRetry)))
                            }
                        }, {
                            return .failure(ErrorEvent(.requestFailed(message: $0.description)))
                        })
                    
                    
                    fulfilled(
                        PsiCashPurchaseResult(
                            purchasable: purchasable,
                            refreshedLibData: psiCash.dataModel,
                            result: mappedResult
                        )
                    )
                }
            },
            modifyLandingPage: { [psiCash, feedbackLogger] url -> Effect<URL> in
                Effect { () -> URL in
                    switch psiCash.modifyLandingPage(url: url.absoluteString) {
                    case .success(let modifiedURL):
                        return URL(string: modifiedURL)!
                    case .failure(let error):
                        feedbackLogger.immediate(.error, "failed to modify url: '\(error))'")
                        return url
                    }
                }
                
            },
            rewardedVideoCustomData: { [psiCash, feedbackLogger] () -> String? in
                switch psiCash.getRewardActivityData() {
                case .success(let rewardActivityData):
                    return rewardActivityData
                case .failure(let error):
                    feedbackLogger.immediate(.error, "GetRewardedActivityDataFailed: '\(error)'")
                    return nil
                }
            },
            removePurchasesNotIn: { [psiCash]
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
                    
                    let result = psiCash.removePurchases(notFoundIn: nonSubscriptionAuthIDs)
                    switch result {
                    case .success(_):
                        return
                    case .failure(let error):
                        feedbackLogger.immediate(.error, "removePurchasesNotIn failed: \(error)")
                    }
                }
            }
        )
    }
    
}
