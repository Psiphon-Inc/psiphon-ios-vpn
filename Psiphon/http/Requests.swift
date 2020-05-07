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

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

enum HTTPContentType: String, HTTPHeader {
    case json = "application/json"
    
    static var headerKey: String { "Content-Type" }
}

/// A success case means that the HTTP request succeeded and server returned a response,
/// the response from the server might itself contain an error.
typealias URLSessionResult = Result<(data: Data, response: HTTPURLResponse), HTTPRequestError>

protocol HTTPHeader {
    static var headerKey: String { get }
}

protocol HTTPResponse {
    associatedtype Success: Equatable
    associatedtype Failure: HashableError
    typealias FailureEvent = ErrorEvent<Failure>
    typealias ResultType = Result<Success, FailureEvent>
    
    var result: ResultType { get }
    
    init(urlSessionResult: URLSessionResult)
}

/// `RetriableHTTPResponse` is an `HTTPResponse` type that determines if a request
/// needs to be retried solely based on the response value.
protocol RetriableHTTPResponse: HTTPResponse {
    
    /// `unpackRetriableResultError` returns `(result: result, retryError: nil)`, if
    /// the request that produced `result` does not need to be retried.
    /// Otherwise returns `(result: result, retryError: .some())`.
    static func unpackRetriableResultError(_ result: ResultType)
        -> (result: ResultType, retryError: FailureEvent?)
    
}

extension RetriableHTTPResponse {
    
    func unpackRetriableResultError() -> (result: ResultType, retryError: FailureEvent?) {
        return Self.unpackRetriableResultError(self.result)
    }
    
}

struct HTTPRequest<Response: HTTPResponse>: Equatable {
    
    let urlRequest: URLRequest
    
    private init(url: URL, body: Data?, clientMetaData: String, method: HTTPMethod,
                 contentType: HTTPContentType, response: Response.Type
    ) {
        var request = URLRequest(
            url: url,
            cachePolicy: UrlRequestParameters.cachePolicy,
            timeoutInterval: UrlRequestParameters.timeoutInterval
        )
        request.httpBody = body
        request.httpMethod = method.rawValue
        request.setValue(contentType.rawValue, forHTTPHeaderField: HTTPContentType.headerKey)
        request.setValue(clientMetaData, forHTTPHeaderField: "X-Verifier-Metadata")
        
        if Debugging.printHttpRequests {
            request.debugPrint()
        }
        
        self.urlRequest = request
    }
    
    /// Makes a HTTP request with a JSON body, by encoding `body`.
    static func json<Body: Encodable>(
        url: URL, body: Body, clientMetaData: String, method: HTTPMethod, response: Response.Type
    ) -> Self {
        do {
            let jsonData = try JSONEncoder.makeRfc3339Encoder().encode(body)
            return .init(url: url, body: jsonData, clientMetaData: clientMetaData,
                         method: method, contentType: .json, response: response)
        } catch {
            fatalError("failed to serialize body '\(body)' error: '\(error)'")
        }
    }
    
}

struct HTTPRequestError: Error {
    /// If a response from the server is received, regardless of whether the request
    /// completes successfully or fails, the response parameter contains that information.
    /// From: https://developer.apple.com/documentation/foundation/urlsession/1410330-datatask
    let partialResponse: HTTPURLResponse?
    let errorEvent: ErrorEvent<SystemError>
}

extension URL {
    
    var isSchemeHttp: Bool {
        switch self.scheme {
        case "http": return true
        case "https": return true
        default: return false
        }
    }
    
}

fileprivate func makeHTTPRequest<Response>(
    _ requestData: HTTPRequest<Response>,
    handler: @escaping (Response) -> Void
) -> URLSessionTask {
    
    guard requestData.urlRequest.url?.isSchemeHttp ?? false else {
        fatalErrorFeedbackLog(
            "Expected HTTP/HTTPS request '\(String(describing: requestData.urlRequest.url))'"
        )
    }
    
    let config = URLSessionConfiguration.ephemeral
    let session = URLSession(configuration: config).dataTask(with: requestData.urlRequest)
    { data, response, error in
        let result: URLSessionResult
        if let error = error {
            // If URLSession task resulted in an error, there might be a partial response.
            result = .failure(HTTPRequestError(partialResponse: response as? HTTPURLResponse,
                                               errorEvent: ErrorEvent(error as SystemError)))
        } else {
            // If `error` is nil, then URLSession task callback guarantees that
            // `data` and `response` are non-nil.
            result = .success((data: data!, response: response! as! HTTPURLResponse))
        }
        handler(Response(urlSessionResult: result))
    }
    session.resume()
    return session
}

struct ClientMetaData: Encodable {
    let clientPlatform: String = AppInfo.clientPlatform()
    let clientRegion: String = AppInfo.clientRegion() ?? ""
    let clientVersion: String = AppInfo.appVersion() ?? ""
    let propagationChannelID: String = AppInfo.propagationChannelId() ?? ""
    let sponsorID: String = AppInfo.sponsorId() ?? ""
    
    
    private enum CodingKeys: String, CodingKey {
        case clientPlatform = "client_platform"
        case clientRegion = "client_region"
        case clientVersion = "client_version"
        case propagationChannelID = "propagation_channel_id"
        case sponsorID = "sponsor_id"
    }
    
    var jsonString: String {
        do {
            let jsonData = try JSONEncoder().encode(ClientMetaData())
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            PsiFeedbackLogger.error(withType: "Requests",
                                    message: "failed to serialize client metadata",
                                    object: error)
        }
        return ""
    }
    
}

/// `httpRequest` makes an HTTP request and returns the result in the returned Effect.
/// Use `RetriableTunneledHttpRequest` if the request needs to be tunneled.
func httpRequest<Response>(
    request urlRequest: HTTPRequest<Response>
) -> Effect<Response> {
    return SignalProducer { observer, lifetime in
        let session = makeHTTPRequest(urlRequest) { response in
            observer.fulfill(value: response)
        }
        lifetime.observeEnded {
            session.cancel()
        }
    }
}

/// Emitted by `tunneledHttpRequest` if tunnel is not connect
/// at the time of the request.
enum HttpRequestTunnelError: HashableError {
    /// Tunnel is not connected.
    case tunnelNotConnected
    /// The weak reference to the tunnel provider manager  is `nil`.
    /// This error is not retriable.
    case nilTunnelProviderManager
    
    var isRetriable: Bool {
        switch self {
        case .tunnelNotConnected: return true
        case .nilTunnelProviderManager: return false
        }
    }
}

/// `tunneledHttpRequest` check tunnel status immediately before sending the HTTP request.
fileprivate func tunneledHttpRequest<Response, T: TunnelProviderManager>(
    request urlRequest: HTTPRequest<Response>,
    tunnelManagerRef: WeakRef<T>
) -> SignalProducer<Response, ErrorEvent<HttpRequestTunnelError>> {
    return SignalProducer { observer, lifetime in
        guard let tunnelManager = tunnelManagerRef.weakRef else {
            observer.send(error: ErrorEvent(.nilTunnelProviderManager))
            observer.sendCompleted()
            return
        }
        let vpnStatus = Debugging.ignoreTunneledChecks ? .connected : tunnelManager.connectionStatus
        guard case .connected = vpnStatus else {
            observer.send(error: ErrorEvent(.tunnelNotConnected))
            observer.sendCompleted()
            return
        }
        let session = makeHTTPRequest(urlRequest) { response in
            observer.fulfill(value: response)
        }
        lifetime.observeEnded {
            session.cancel()
        }
    }
}

struct RetriableTunneledHttpRequest<Response: RetriableHTTPResponse> {
        
    /// `SignalTermination` represents whether the authorization request signal has completed,
    /// and that the signal should be completed.
    private enum SignalTermination: Equatable {
        case value(RequestResult)
        case terminate
    }
    
    /// `RetriableTunneledHttpResult` wraps possible values from `retriableTunneledHttpRequest` function call.
    enum RequestResult: Equatable {
        
        enum RetryCondition: Equatable {
            case tunnelConnected
            case afterTimeInterval(interval: DispatchTimeInterval, result: Response.ResultType)
        }
        
        /// Request will be retried after the given condition is met.
        case willRetry(when: RetryCondition)
        
        /// Request failed and will not be retried.
        case failed(ErrorEvent<RequestError>)
        
        /// Request is completed and will not be retried.
        case completed(Response.ResultType)
    }
    
    enum RequestError: HashableError {
        /// Request error due to tunnel error.
        case tunnelError(HttpRequestTunnelError)
        /// Request error due to response indicating a retry is needed.
        case responseRetryError(Response.Failure)
    }
    
    let request: HTTPRequest<Response>
    let retryCount: Int = 5
    let retryInterval: DispatchTimeInterval = .seconds(1)
    
    func makeRequestSignal<T: TunnelProviderManager>(
        tunnelStatusWithIntentSignal: SignalProducer<VPNStatusWithIntent, Never>,
        tunnelManagerRef: WeakRef<T>
    ) -> Effect<RequestResult>
    {
        tunnelStatusWithIntentSignal
            .skipRepeats()
            .combinePrevious(initial: VPNStatusWithIntent(status: .invalid, intent: nil))
            .take(while: { combined -> Bool in
                // Takes values while either of the following cases is true:
                // - Intent value of .start(.none) is not observed.
                // - After transitioning to .start(.none), the intent does not change.
                
                if Debugging.ignoreTunneledChecks {
                    return true
                }
                
                switch (combined.previous.intent, combined.current.intent) {
                case (.start(transition: .none), .start(transition: .none)):
                    return true
                case (_, .start(transition: .none)):
                    return true
                case (.start(transition: .none), _):
                    return false
                case (_, _):
                    return true
                }
            })
            .filter {
                if Debugging.ignoreTunneledChecks {
                    return true
                }
                
                // Filters out values until the intent value changes to .start(.none)
                return $0.current.intent == .some(.start(transition: .none))
        }
        .map(\.current.status)
        .skipRepeats()
        .flatMap(.latest) { value -> SignalProducer<SignalTermination, ErrorEvent<RequestError>> in
            let vpnStatus = Debugging.ignoreTunneledChecks ? .connected : value
            guard case .connected = vpnStatus else {
                return SignalProducer(value: .value(.willRetry(when: .tunnelConnected)))
            }
            
            // Signal invariant:
            // Tunnel intent is .start(.none) and VPN status is connected.
            
            return tunneledHttpRequest(
                request: self.request,
                tunnelManagerRef: tunnelManagerRef
            ).mapError { tunnelErrorEvent -> ErrorEvent<RequestError> in
                tunnelErrorEvent.map { .tunnelError($0) }
            }
            .flatMap(.latest) { (response: Response)
                -> SignalProducer<SignalTermination, ErrorEvent<RequestError>> in
                
                // Determines if the request needs to be retried.
                let (result, maybeRetryError) = response.unpackRetriableResultError()
                
                if let retryError = maybeRetryError {
                    let errorValue = retryError.map(RequestError.responseRetryError)
                    // Request needs to be retried.
                    return SignalProducer(error: errorValue)
                        .prefix(value:
                            .value(
                                .willRetry(when:
                                    .afterTimeInterval(interval: self.retryInterval, result: result)
                                )
                            ))
                } else {
                    // Request is complete and does not need to be retried.
                    return SignalProducer(value: .terminate)
                        .prefix(value: .value(.completed(result)))
                }
            }
            .flatMapError { requestErrorEvent
                -> SignalProducer<SignalTermination, ErrorEvent<RequestError>> in
                
                // If the tunnel error request is not retriable, then the signal is completed
                // and no further retries are carried out.
                // Otherwise, the error is retriable and is simply forwarded.
                
                guard case let .tunnelError(tunnelError) = requestErrorEvent.error else {
                    return SignalProducer(error: requestErrorEvent)
                }
                if tunnelError.isRetriable {
                    return SignalProducer(error: requestErrorEvent)
                } else {
                    return SignalProducer(value: .terminate)
                        .prefix(value: .value(.failed(requestErrorEvent)))
                }
            }
            .retry(upTo: self.retryCount,
                   interval: self.retryInterval.toDouble()!,
                   on: QueueScheduler.main)
            
        }
        .flatMapError { (requestErrorEvent: ErrorEvent<RequestError>) -> Effect<SignalTermination> in
            return Effect(value: .value(.failed(requestErrorEvent)))
        }
        .take(while: { signalTermination -> Bool in
            // Forwards values while the `.terminate` value has not been emitted.
            guard case .value(_) = signalTermination else {
                return false
            }
            return true
        }).map { signalTermination -> RequestResult in
                guard case let .value(requestResult) = signalTermination else {
                    fatalError()
                }
                return requestResult
        }.on(completed: {
            PsiFeedbackLogger.info(withType: "RetriableTunneledHttpRequest",
                                   message: "SignalCompleted")
        })
    }
    
}

extension RetriableTunneledHttpRequest : Equatable {}
