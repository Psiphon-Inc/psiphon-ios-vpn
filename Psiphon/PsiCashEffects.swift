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
        case .existingTransaction:
            return UserStrings.Speed_boost_you_already_have()
        case .insufficientBalance:
            return UserStrings.Insufficient_psiCash_balance()
        case .transactionTypeNotFound:
            return UserStrings.PsiCash_speed_boost_product_not_found_update_app_message()
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

/// Result of an HTTP request made by the PsiCash library.
fileprivate struct PsiCashHTTPResponse: HTTPResponse {
    
    /// Represents an HTTP respose.
    struct Response: Equatable {
        let code: Int32
        let headers: [String: [String]]
        let body: String
    }
    
    typealias Success = Response
    typealias Failure = ErrorMessage
    
    /// Represents result of an HTTP request.
    var result: ResultType
    
    /// `PSIHttpResult` value to be consumed by the PsiCash library.
    var psiHTTPResult: PSIHttpResult {
        switch result {
        case .success(let success):
            return PSIHttpResult(
                code: success.code,
                headers: success.headers,
                body: success.body,
                error: ""
            )
            
        case .failure(let errorEvent):
            return PSIHttpResult(recoverableError: "\(errorEvent.error)")
        }
    }
    
    init(urlSessionResult: URLSessionResult) {
        switch urlSessionResult.result {
        case let .success(r):
            
            let statusCode = Int32(r.metadata.statusCode.rawValue)
            
            guard let body = String(data: r.data, encoding: .utf8) else {
                result = .failure(
                    ErrorEvent(ErrorMessage("Failed to decode body: size: \(r.data.count)"),
                               date: urlSessionResult.date)
                )
                return
            }
            
            result = .success(
                Response(code: statusCode,
                         headers: r.metadata.headers.mapValues { [$0] },
                         body: body)
            )
            
        case let .failure(httpRequestError):
            // In the case of a partial response, a `RECOVERABLE_ERROR` should be returned.
            result = .failure(
                ErrorEvent(ErrorMessage("Request failed. Error: \(httpRequestError)"),
                           date: urlSessionResult.date)
            )
        }
    }
    
}

/// Reducers should only use PsiCashEffects instead of directly accessing PsiCashLib.
/// TODO: PsiCashLib should become a service actor once that feature lands in Swift.
final class PsiCashEffects: PsiCashEffectsProtocol {
    
    private let psiCashLib: PsiCashLib
    private let httpClient: HTTPClient
    private let globalDispatcher: GlobalDispatcher
    private let getCurrentTime: () -> Date
    private let feedbackLogger: FeedbackLogger
    
    init(
        psiCashLib: PsiCashLib,
        httpClient: HTTPClient,
        globalDispatcher: GlobalDispatcher,
        getCurrentTime: @escaping () -> Date,
        feedbackLogger: FeedbackLogger
    ) {
        self.psiCashLib = psiCashLib
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
            
            let initResult = self.psiCashLib.initialize(
                userAgent: PsiCashClientHardCodedValues.userAgent,
                fileStoreRoot: fileStoreRoot,
                psiCashLegacyDataStore: psiCashLegacyDataStore,
                httpRequestFunc: { (request: PSIHttpRequest) -> PSIHttpResult in
                
                    // All recoverable errors are logged immediatley.
                    // This is useful for tracking failed requests that succeeded eventually.
                    
                    // Synchronous check for tunnel connection status.
                    
                    // Blocks until the first value is received.
                    // TODO: Replace with actors once it is introduced to Swift.
                    guard
                        case .some(.success(.some(let tunnelConnection))) =
                            tunnelConnectionRefSignal.first()
                    else {
                        self.feedbackLogger.immediate(.error, "VPN config not installed")
                        return PSIHttpResult(recoverableError: "VPN config not installed")
                    }
                    
                    guard case .connected = tunnelConnection.tunneled else {
                        self.feedbackLogger.immediate(.error, "Psiphon tunnel is not connected")
                        return PSIHttpResult(recoverableError: "Psiphon tunnel is not connected")
                    }
                    
                    // Maps [PSIPair<NSString>] to Swift type `[(String, String)]`.
                    let queryParams: [(String, String)] = request.query.map {
                        ($0.first as String, $0.second as String)
                    }
                    
                    guard let httpMethod = HTTPMethod(rawValue: request.method) else {
                        return PSIHttpResult(
                            criticalError: "Failed to parse HTTP method '\(request.method)'")
                    }
                    
                    let maybeUrl = URL.make(scheme: request.scheme,
                                            hostname: request.hostname,
                                            port: request.port,
                                            path: request.path,
                                            queryParams: queryParams)
                    
                    guard let url = maybeUrl else {
                        return PSIHttpResult(criticalError: "Failed to create URL")
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
                
                    // Logs error probably caused by a network failure.
                    if case .failure(let errorEvent) = response!.result {
                        self.feedbackLogger.immediate(
                            .error, "PsiCash HTTP request failed: \(errorEvent.error)")
                    }
                    
                    return response!.psiHTTPResult
                },
                test: Debugging.devServers)
            
            switch initResult {
            case .success(let requiredStateRefresh):
                return .success(
                    PsiCashLibInitSuccess(
                        libData: self.psiCashLib.dataModel,
                        requiresStateRefresh: requiredStateRefresh
                    )
                )
            case .failure(let error):
                return .failure(ErrorRepr(repr: String(describing: error)))
            }
        }
    }
    
    func libData() -> PsiCashLibData {
        return self.psiCashLib.dataModel
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
            let maybeError = self.psiCashLib.setRequestMetadata(clientMetaData)
            guard maybeError == nil else {
                self.feedbackLogger.fatalError("failed to set request metadata")
                return
            }
            
            let purchaseClasses = priceClasses.map(\.rawValue)
            
            // Blocking call.
            let result = self.psiCashLib.refreshState(purchaseClasses: purchaseClasses,
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
                        refreshedLibData: self.psiCashLib.dataModel,
                        result: .failure(ErrorEvent(.tunnelNotConnected,
                                                    date: self.getCurrentTime())))
                )
                return
            }
            
            self.feedbackLogger.immediate(.info,
                                     "Purchase: '\(String(describing: purchasable))'")
            
            // Updates request metadata before sending the request.
            let maybeError = self.psiCashLib.setRequestMetadata(clientMetaData)
            guard maybeError == nil else {
                self.feedbackLogger.fatalError("failed to set request metadata")
                return
            }
            
            // Blocking call.
            let result = self.psiCashLib.newExpiringPurchase(purchasable: purchasable)
            
            fulfilled(
                NewExpiringPurchaseResult(
                    refreshedLibData: self.psiCashLib.dataModel,
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
            switch self.psiCashLib.modifyLandingPage(url: url.absoluteString) {
            case .success(let modifiedURL):
                return URL(string: modifiedURL)!
            case .failure(let error):
                self.feedbackLogger.immediate(.error, "failed to modify url: '\(error))'")
                return url
            }
        }
        
    }
    
    func getUserSiteURL(_ urlType: PSIUserSiteURLType, webview: Bool) -> URL {
        psiCashLib.getUserSiteURL(urlType, webview: webview)
    }
    
    func rewardedVideoCustomData() -> String? {
        
        switch self.psiCashLib.getRewardActivityData() {
        
        case .success(let rewardActivityData):
            return rewardActivityData
            
        case .failure(let error):
            self.feedbackLogger.immediate(.error, "GetRewardedActivityDataFailed: '\(error)'")
            return nil
            
        }
        
    }
    
    func removePurchases(
        withTransactionIDs transactionIds: [String]
    ) -> Effect<Result<[PsiCashParsed<PsiCashPurchasedType>], PsiCashLibError>> {
        
        Effect.deferred(dispatcher: globalDispatcher) { fulfill in
            fulfill(self.psiCashLib.removePurchases(withTransactionIDs: transactionIds))
        }
        
    }
    
    func accountLogout() -> Effect<PsiCashAccountLogoutResult> {
        
        Effect.deferred(dispatcher: globalDispatcher) { fulfilled in
            
            // This may involve a network operation and so can be blocking.
            
            fulfilled(
                self.psiCashLib.accountLogout()
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
            let result = self.psiCashLib.accountLogin(username: username, password: password)
            
            fulfilled(
                result.mapError {
                    ErrorEvent(.requestError($0), date: self.getCurrentTime())
                }
            )
        }
        
    }
    
    func setLocale(_ locale: Locale) -> Effect<Never> {
        
        .fireAndForget {
            guard let error = self.psiCashLib.setLocale(locale) else {
                return
            }
            self.feedbackLogger.immediate(.error, "setLocale failed: \(error)")
        }
        
    }

}
