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
import ReactiveSwift

extension PsiCashRequestError: LocalizedUserDescription where ErrorStatus: LocalizedUserDescription {
    
    public var localizedUserDescription: String {
        switch self {
        case .errorStatus(let errorStatus):
            return errorStatus.localizedUserDescription
        case .requestCatastrophicFailure(let psiCashLibError):
            return psiCashLibError.localizedDescription
        }
    }
    
}

extension TunneledPsiCashRequestError: LocalizedUserDescription where
    RequestError: LocalizedUserDescription {

    public var localizedUserDescription: String {
        switch self {
        case .tunnelNotConnected:
            return UserStrings.Psiphon_is_not_connected()
        case .requestError(let requestError):
            return requestError.localizedUserDescription
        }
    }

}

extension PsiCashNewExpiringPurchaseErrorStatus: LocalizedUserDescription {
    
    public var localizedUserDescription: String {
        switch self {
        case .insufficientBalance:
            return UserStrings.Insufficient_psiCash_balance()
        default:
            return UserStrings.Operation_failed_please_try_again_alert_message()
        }
    }
    
}

extension PsiCashNewExpiringPurchaseErrorStatus {
    
    /// Whether or not the request should be retried given this status.
    var shouldRetry: Bool {
        switch self {
        case .serverError:
            return true
        case .existingTransaction,
             .insufficientBalance,
             .transactionAmountMismatch,
             .transactionTypeNotFound,
             .invalidTokens:
            return false
        }
    }
    
}

extension PsiCashAmount: CustomStringFeedbackDescription {
    
    public var description: String {
        "PsiCash(inPsi: \(String(format: "%.2f", self.inPsi)))"
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
        switch urlSessionResult.result {
        case let .success(r):
            
            let statusCode = Int32(r.metadata.statusCode.rawValue)
            
            guard let body = String(data: r.data, encoding: .utf8) else {
                result = .success(PSIHttpResult(criticalError: ()))
                return
            }
            
            let psiHttpResult = PSIHttpResult(
                code: statusCode,
                headers: r.metadata.headers.mapValues { [$0] },
                body: body,
                error: "")
            
            result = .success(psiHttpResult)
            
        case let .failure(httpRequestError):
            if let partialResponse = httpRequestError.partialResponseMetadata {
                let statusCode = Int32(partialResponse.statusCode.rawValue)
                
                let psiHttpResult = PSIHttpResult(
                    code: statusCode,
                    headers: partialResponse.headers.mapValues { [$0] },
                    body: "",
                    error: "")
                
                result = .success(psiHttpResult)
                
            } else {
                let psiHttpResult = PSIHttpResult(
                    code: PSIHttpResult.recoverable_ERROR(),
                    headers: [String: [String]](),
                    body: "",
                    error: "")
                
                result = .success(psiHttpResult)
            }
        }
    }
    
}


final class PsiCashEffects: PsiCashEffectsProtocol {
    
    private let psiCash: PsiCashLib
    private let httpClient: HTTPClient
    private let globalDispatcher: GlobalDispatcher
    private let getCurrentTime: () -> Date
    private let feedbackLogger: FeedbackLogger
    
    init(
        psiCashClient: PsiCashLib,
        httpClient: HTTPClient,
        globalDispatcher: GlobalDispatcher,
        getCurrentTime: @escaping () -> Date,
        feedbackLogger: FeedbackLogger
    ) {
        self.psiCash = psiCashClient
        self.httpClient = httpClient
        self.globalDispatcher = globalDispatcher
        self.getCurrentTime = getCurrentTime
        self.feedbackLogger = feedbackLogger
    }
    
    func initialize(
        fileStoreRoot: String?,
        psiCashLegacyDataStore: UserDefaults,
        tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    ) -> Effect<Result<PsiCashLibInitSuccess, ErrorRepr>> {
        
        Effect { () -> Result<PsiCashLibInitSuccess, ErrorRepr> in

            guard let fileStoreRoot = fileStoreRoot else {
                return .failure(ErrorRepr(repr: "nil psicash file store root"))
            }
            
            let initResult = self.psiCash.initialize(
                userAgent: PsiCashClientHardCodedValues.userAgent,
                fileStoreRoot: fileStoreRoot,
                psiCashLegacyDataStore: psiCashLegacyDataStore,
                httpRequestFunc: { (request: PSIHttpRequest) -> PSIHttpResult in
                    
                    // Synchronous check for tunnel connection status.
                    
                    // Blocks until the first value is received.
                    // TODO: Replace with actors once it is introduced to Swift.
                    guard
                        case .some(.success(.some(let tunnelConnection))) =
                            tunnelConnectionRefSignal.first()
                    else {
                        return PSIHttpResult(recoverableError: ())
                    }
                    
                    guard case .connected = tunnelConnection.tunneled else {
                        return PSIHttpResult(recoverableError: ())
                    }
                    
                    // Maps [PSIPair<NSString>] to Swift type `[(String, String)]`.
                    let queryParams: [(String, String)] = request.query.map {
                        ($0.first as String, $0.second as String)
                    }
                    
                    guard let httpMethod = HTTPMethod(rawValue: request.method) else {
                        return PSIHttpResult(criticalError: ())
                    }
                    
                    let maybeUrl = URL.make(scheme: request.scheme,
                                            hostname: request.hostname,
                                            port: request.port,
                                            path: request.path,
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
                    let _ = self.httpClient.request(self.getCurrentTime, httpRequest) {
                        response = $0
                        sem.signal()
                    }
                    sem.wait()
                    
                    return response!.psiHTTPResult
                },
                test: Debugging.devServers)
            
            switch initResult {
            case .success(let requiredStateRefresh):
                return .success(
                    PsiCashLibInitSuccess(
                        libData: self.psiCash.dataModel,
                        requiresStateRefresh: requiredStateRefresh
                    )
                )
            case .failure(let error):
                return .failure(ErrorRepr(repr: String(describing: error)))
            }
        }
    }
    
    func libData() -> PsiCashLibData {
        return self.psiCash.dataModel
    }
    
    func refreshState(
        priceClasses: [PsiCashTransactionClass],
        tunnelConnection: TunnelConnection,
        clientMetaData: ClientMetaData
    ) -> Effect<PsiCashRefreshResult> {
        
        Effect.deferred(dispatcher: self.globalDispatcher) { fulfilled in
            
            // If we are not connected, calls refreshState
            // with localOnly set to true.
            let localOnly = tunnelConnection.tunneled != .connected
            
            // Updates request metadata before sending the request.
            let maybeError = self.psiCash.setRequestMetadata(clientMetaData)
            guard maybeError == nil else {
                self.feedbackLogger.fatalError("failed to set request metadata")
                return
            }
            
            let purchaseClasses = priceClasses.map(\.rawValue)
            
            // Blocking call.
            let result = self.psiCash.refreshState(purchaseClasses: purchaseClasses,
                                              localOnly: localOnly)
            
            fulfilled(
                result.mapError {
                    ErrorEvent($0, date: self.getCurrentTime())
                }
            )
            
        }
        
    }
    
    func purchaseProduct(
        purchasable: PsiCashPurchasableType,
        tunnelConnection: TunnelConnection,
        clientMetaData: ClientMetaData
    ) -> Effect<NewExpiringPurchaseResult> {
        
        Effect.deferred(dispatcher: self.globalDispatcher) { fulfilled in
            guard case .connected = tunnelConnection.tunneled else {
                fulfilled(
                    NewExpiringPurchaseResult(
                        refreshedLibData: self.psiCash.dataModel,
                        result: .failure(ErrorEvent(.tunnelNotConnected,
                                                    date: self.getCurrentTime())))
                )
                return
            }
            
            self.feedbackLogger.immediate(.info,
                                     "Purchase: '\(String(describing: purchasable))'")
            
            // Updates request metadata before sending the request.
            let maybeError = self.psiCash.setRequestMetadata(clientMetaData)
            guard maybeError == nil else {
                self.feedbackLogger.fatalError("failed to set request metadata")
                return
            }
            
            // Blocking call.
            let result = self.psiCash.newExpiringPurchase(purchasable: purchasable)
            
            fulfilled(
                NewExpiringPurchaseResult(
                    refreshedLibData: self.psiCash.dataModel,
                    result: result.mapError {
                        return ErrorEvent(.requestError($0),
                                          date: self.getCurrentTime())
                    }
                )
            )
        }
        
    }
    
    func modifyLandingPage(_ url: URL) -> Effect<URL> {
        
        Effect { () -> URL in
            switch self.psiCash.modifyLandingPage(url: url.absoluteString) {
            case .success(let modifiedURL):
                return URL(string: modifiedURL)!
            case .failure(let error):
                self.feedbackLogger.immediate(.error, "failed to modify url: '\(error))'")
                return url
            }
        }
        
    }
    
    func rewardedVideoCustomData() -> String? {
        
        switch self.psiCash.getRewardActivityData() {
        
        case .success(let rewardActivityData):
            return rewardActivityData
            
        case .failure(let error):
            self.feedbackLogger.immediate(.error, "GetRewardedActivityDataFailed: '\(error)'")
            return nil
            
        }
        
    }
    
    func removePurchasesNotIn(
        psiCashAuthorizations: Set<String>
    ) -> Effect<Never> {
        
        .fireAndForget {
            let decoder = JSONDecoder.makeRfc3339Decoder()
            
            let nonSubscriptionAuthIDs = psiCashAuthorizations
                .compactMap { encodedAuth -> SignedAuthorization? in
                    guard let data = encodedAuth.data(using: .utf8) else {
                        return nil;
                    }
                    return try? decoder.decode(SignedAuthorization.self, from: data)
                }.map(\.authorization.id)
            
            let result = self.psiCash.removePurchases(notFoundIn: nonSubscriptionAuthIDs)
            switch result {
            case .success(_):
                return
            case .failure(let error):
                self.feedbackLogger.immediate(.error, "removePurchasesNotIn failed: \(error)")
            }
        }
        
    }
    
    func accountLogout() -> Effect<PsiCashAccountLogoutResult> {
        
        Effect.deferred(dispatcher: globalDispatcher) { fulfilled in
            
            // This may involve a network operation and so can be blocking.
            
            fulfilled(
                self.psiCash.accountLogout()
                    .mapError { ErrorEvent($0, date: self.getCurrentTime()) }
            )
        }
        
    }
    
    func accountLogin(
        tunnelConnection: TunnelConnection,
        username: String,
        password: SecretString
    ) -> Effect<PsiCashAccountLoginResult> {
        
        Effect.deferred(dispatcher: globalDispatcher) { fulfilled in
            
            guard case .connected = tunnelConnection.tunneled else {
                fulfilled(
                    .failure(ErrorEvent(.tunnelNotConnected, date: self.getCurrentTime()))
                )
                return
            }
            
            // This is a blocking call.
            let result = self.psiCash.accountLogin(username: username, password: password)
            
            fulfilled(
                result.mapError {
                    ErrorEvent(.requestError($0), date: self.getCurrentTime())
                }
            )
        }
        
    }
    
    func setLocale(_ locale: Locale) -> Effect<Never> {
        
        .fireAndForget {
            guard let error = self.psiCash.setLocale(locale) else {
                return
            }
            self.feedbackLogger.immediate(.error, "setLocale failed: \(error)")
        }
        
    }

}
