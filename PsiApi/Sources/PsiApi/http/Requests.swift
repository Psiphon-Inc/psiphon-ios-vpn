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

extension URL {
    
    public static func make(scheme: String, hostname: String, port: Int32,
          path: String, queryParams: [(field: String, value: String)]) -> URL? {

        // Syntax components of URLs: https://tools.ietf.org/html/rfc3986#section-3
        
        let query = queryParams.map { "\($0.field)=\($0.value)" }
            .joined(separator: "&")
        
        let authority = "\(hostname):\(port)"
        
        let queryString = query.isEmpty ? "" : "?\(query)"
        
        return URL(string: "\(scheme)://\(authority)\(path)\(queryString)")
    }
    
}

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

public enum HTTPContentType: String, HTTPHeader {
    case json = "application/json"
    
    public static let headerKey = "Content-Type"
}

public struct HTTPDateHeader: HTTPHeader {
    
    public let value: String
    
    public init(_ value: String) {
        self.value = value
    }
    
    public static let headerKey = "Date"
}

public struct HTTPResponseData: Hashable {
    public let metadata: HTTPResponseMetadata
    public let data: Data

    public init(data: Data, metadata: HTTPResponseMetadata) {
        self.data = data
        self.metadata = metadata
    }
}

public struct HTTPResponseMetadata: Hashable {
    public let url: URL
    public let headers: [String: String]
    public let statusCode: Int
    /// respStatus is typed `statusCode`.
    /// `nil` represents an uknown status code.
    public let respStatus: HTTPStatusCode?
    
    public init(url: URL, headers: [String: String], statusCode: Int) {
        self.url = url
        self.headers = headers
        self.statusCode = statusCode
        self.respStatus = HTTPStatusCode(rawValue: statusCode)
    }
    
    public init(_ httpURLResponse: HTTPURLResponse) {
        self.url = httpURLResponse.url!
        self.headers = httpURLResponse.allHeaderFields as! [String: String]
        self.statusCode = httpURLResponse.statusCode
        self.respStatus = HTTPStatusCode(rawValue: httpURLResponse.statusCode)
    }
}


public struct URLSessionResult: Equatable {
    
    /// Date that the result was produced.
    public let date: Date
    
    /// A success case means that the HTTP request succeeded and server returned a response,
    /// the response from the server might itself contain an error.
    public let result: Result<HTTPResponseData, HTTPRequestError>
    
    public init(date: Date, result: Result<HTTPResponseData, HTTPRequestError>) {
        self.date = date
        self.result = result
    }
}

public protocol HTTPHeader {
    static var headerKey: String { get }
}

public protocol HTTPResponse {
    associatedtype Success: Equatable
    associatedtype Failure: HashableError
    typealias FailureEvent = ErrorEvent<Failure>
    
    typealias ResultType = Result<Success, FailureEvent>
    
    var result: ResultType { get }
    
    init(urlSessionResult: URLSessionResult)
}

/// `RetriableHTTPResponse` is an `HTTPResponse` type that determines if a request
/// needs to be retried solely based on the response value.
public protocol RetriableHTTPResponse: HTTPResponse {
    
    /// `unpackRetriableResultError` returns `(result: result, retryDueToError: nil)`, if
    /// the request that produced `result` does not need to be retried.
    /// Otherwise returns `(result: result, retryDueToError: .some())`.
    static func unpackRetriableResultError(_ result: ResultType)
        -> (result: ResultType, retryDueToError: FailureEvent?)
    
}

extension RetriableHTTPResponse {
    
    public func unpackRetriableResultError() ->
    (result: ResultType, retryDueToError: FailureEvent?)
    {
        return Self.unpackRetriableResultError(self.result)
    }
    
}

/// Represents a HTTP request.
/// `Response` is a phantom type.
public struct HTTPRequest<Response: HTTPResponse>: Equatable {
    
    let urlRequest: URLRequest
    
    public init(url: URL, httpMethod: HTTPMethod, headers: [String: String],
                body: Data?, response: Response.Type) {
        var request = URLRequest(
            url: url,
            cachePolicy: UrlRequestParameters.cachePolicy,
            timeoutInterval: UrlRequestParameters.timeoutInterval
        )
        
        request.httpMethod = httpMethod.rawValue
        request.httpBody = body
        
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        
        if Debugging.printHttpRequests {
            request.debugPrint()
        }
        
        self.urlRequest = request
    }
    
    /// Makes a HTTP request with a JSON body.
    public static func json(
        url: URL, jsonData: Data, clientMetaData: String, method: HTTPMethod,
        response: Response.Type
    ) -> Self {
        let headers = [HTTPContentType.headerKey: HTTPContentType.json.rawValue,
                       "X-Verifier-Metadata": clientMetaData]
        return .init(url: url, httpMethod: method, headers: headers,
                     body: jsonData, response: response)
    }
    
}

public struct HTTPRequestError: HashableError {
    /// If a response from the server is received, regardless of whether the request
    /// completes successfully or fails, the response parameter contains that information.
    /// From: https://developer.apple.com/documentation/foundation/urlsession/1410330-datatask
    public let partialResponseMetadata: HTTPResponseMetadata?
    public let error: SystemError<Int>
    
    public init(
        partialResponseMetadata: HTTPResponseMetadata?,
        error: SystemError<Int>
    ) {
        self.partialResponseMetadata = partialResponseMetadata
        self.error = error
    }
    
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

/// Emitted by `tunneledHttpRequest` if tunnel is not connect
/// at the time of the request.
public enum HttpRequestTunnelError: String, CaseIterable, HashableError {
    /// Tunnel is not connected.
    case tunnelNotConnected
    /// The weak reference to the tunnel provider manager  is `nil`.
    /// This error is not retriable.
    case nilTunnelProviderManager
}


public protocol CancellableURLRequest {
    func cancel()
}

extension URLSessionTask: CancellableURLRequest {}


public struct HTTPClient {
    
    public typealias RequestFunc = (
        @escaping () -> Date,
        URLSession,
        URLRequest,
        @escaping (URLSessionResult) -> Void
        ) -> CancellableURLRequest
    
    let session: URLSession
    
    private let makeRequest: RequestFunc

    public init(urlSession: URLSession, _ makeRequest: @escaping RequestFunc) {
        self.session = urlSession
        self.makeRequest = makeRequest
    }
    
    public func request<Response>(
        _ getCurrentTime: @escaping () -> Date,
        _ requestData: HTTPRequest<Response>,
        handler: @escaping (Response) -> Void
    ) -> CancellableURLRequest {
        
        guard requestData.urlRequest.url?.isSchemeHttp ?? false else {
            fatalError(
                "Expected HTTP/HTTPS request '\(String(describing: requestData.urlRequest.url))'"
            )
        }
        
        return self.makeRequest(getCurrentTime, self.session, requestData.urlRequest) { result in
            handler(Response(urlSessionResult: result))
        }
        
    }
    
}

/// `tunneledHttpRequest` check tunnel status immediately before sending the HTTP request.
fileprivate func tunneledHttpRequest<Response>(
    getCurrentTime: @escaping () -> Date,
    request urlRequest: HTTPRequest<Response>,
    tunnelConnection: TunnelConnection,
    httpClient: HTTPClient
) -> SignalProducer<Response, ErrorEvent<HttpRequestTunnelError>> {
    return SignalProducer { observer, lifetime in
        
        switch tunnelConnection.connectionStatus() {
        case .resourceReleased:
            observer.send(error: ErrorEvent(.nilTunnelProviderManager, date: getCurrentTime()))
            observer.sendCompleted()
            return
            
        case .connection(let connection):
            let vpnStatus = Debugging.ignoreTunneledChecks ? .connected : connection
            guard case .connected = vpnStatus else {
                observer.send(error: ErrorEvent(.tunnelNotConnected, date: getCurrentTime()))
                observer.sendCompleted()
                return
            }
            let session = httpClient.request(getCurrentTime, urlRequest) { response in
                observer.fulfill(value: response)
            }
            lifetime.observeEnded {
                session.cancel()
            }
        }
    }
}

public struct RetriableTunneledHttpRequest<Response: RetriableHTTPResponse>: Equatable {
    
    /// `RequestResult` represents all values that can be emitted by the returned Effect.
    public enum RequestResult: Equatable {
        
        /// `RetryCondition` represents the conditions that need to resolved in order for the request
        /// to be retried automatically.
        public enum RetryCondition: Equatable {
            
            /// Request will not be retried until the `tunnelError` error is resolved.
            case whenResolved(tunnelError: HttpRequestTunnelError)
            
            /// Request will be retried automatically after the given internal.
            case afterTimeInterval(interval: DispatchTimeInterval, result: Response.ResultType)
            
        }
        
        /// Request will be retried according to RetryCondition.
        case willRetry(RetryCondition)
        
        /// Request is completed and will not be retried.
        /// This is a terminal value.
        case completed(Response.ResultType)
        
    }
    
    /// RetryError represents errors that can be retried automatically.
    /// - Errors of type`.tunnelError` are tunnel-related issues and
    /// are not retried immediately until some condition given the app state is met.
    /// - Errors of type `.responseRetryError` are errors originating from
    /// the request response (e.g. a 200-OK response that contains an error in it's body),
    /// and can be retried automatically regardless of other app state.z
    private enum RetryError: HashableError {
        /// Request error due to tunnel error.
        case tunnelError(HttpRequestTunnelError)
        /// Request error due to response indicating a retry is needed.
        case responseRetryError(Response.Failure)
    }

    let request: HTTPRequest<Response>
    let retryCount: Int
    let retryInterval: DispatchTimeInterval
    
    public init(request: HTTPRequest<Response>, retryCount: Int = 5,
         retryInterval: DispatchTimeInterval = .seconds(1)) {
        self.request = request
        self.retryCount = retryCount
        self.retryInterval = retryInterval
    }
    
    public func callAsFunction(
        getCurrentTime: @escaping () -> Date,
        tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>,
        tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
        httpClient: HTTPClient
    ) -> Effect<RequestResult>
    {
        tunnelStatusSignal
        .combineLatest(with: tunnelConnectionRefSignal)
        .skipRepeats({ (lhs, rhs) -> Bool in
            return lhs.0 == rhs.0 && lhs.1 == rhs.1
        })
        .flatMap(.latest) { (value: (TunnelProviderVPNStatus, TunnelConnection?))
            -> SignalProducer<SignalTermination<RequestResult>, ErrorEvent<Response.Failure>> in
            
            let vpnStatus = Debugging.ignoreTunneledChecks ? .connected : value.0
            guard case .connected = vpnStatus else {
                return SignalProducer(value: .value(.willRetry(.whenResolved(tunnelError: .tunnelNotConnected))))
            }
            
            guard let tunnelConnection = value.1 else {
                return SignalProducer(value: .value(.willRetry(
                    .whenResolved(tunnelError: .nilTunnelProviderManager))))
            }
            
            // Signal invariant:
            // Tunnel intent is .start(.none), VPN status is connected and tunnel manager is loaded.
            return tunneledHttpRequest(
                getCurrentTime: getCurrentTime,
                request: self.request,
                tunnelConnection: tunnelConnection,
                httpClient: httpClient
            ).mapError { (tunnelErrorEvent: ErrorEvent<HttpRequestTunnelError>)
                -> ErrorEvent<RetryError> in
                
                tunnelErrorEvent.map { .tunnelError($0) }
            }
            .flatMap(.latest) { (response: Response)
                -> SignalProducer<SignalTermination<RequestResult>, ErrorEvent<RetryError>> in
                
                // Determines if the request needs to be retried.
                let (result, maybeRetryDueToError) = response.unpackRetriableResultError()
                
                if let retryDueToError = maybeRetryDueToError {
                    let errorValue = retryDueToError.map(RetryError.responseRetryError)
                    // Request needs to be retried.
                    return SignalProducer(error: errorValue)
                        .prefix(value:.value(.willRetry(
                            .afterTimeInterval(interval: self.retryInterval, result: result))))
                        .map { (a: SignalTermination<RetriableTunneledHttpRequest<Response>.RequestResult>) in
                            print("* retry \(a)")
                            return a
                        }
                } else {
                    // Request is completed and does not need to be retried.
                    return SignalProducer(value: .terminate)
                        .prefix(value: .value(.completed(result)))
                }
            }
            .flatMapError { (requestRetryErrorEvent: ErrorEvent<RetryError>)
                -> SignalProducer<SignalTermination<RequestResult>, ErrorEvent<Response.Failure>> in
                
                // If the tunnel error request is not retriable, then the signal is completed
                // and no further retries are carried out.
                // Otherwise, the error is retriable and is simply forwarded.
                switch requestRetryErrorEvent.error {
                case .tunnelError(let tunnelError):
                    // Tunnel errors should be resolved from upstream,
                    // hence error is converted to a value and passed downstream.
                    // These errors will not terminate the signal.
                    return SignalProducer.neverComplete(value:
                        .value(.willRetry(.whenResolved(tunnelError: tunnelError))))
                    
                case .responseRetryError(let responseError):
                    // Error is due to retrieved response for the request,
                    // and is forwarded downstream to be retried.
                    return SignalProducer(error: requestRetryErrorEvent.map { _ in
                        return responseError
                    })
                }
                
            }
            .retry(upTo: self.retryCount,
                   interval: self.retryInterval.toDouble()!,
                   on: QueueScheduler(qos: .default, name: "RetryScheduler"))
        }
        .flatMapError { (responseError: ErrorEvent<Response.Failure>)
            -> Effect<SignalTermination<RequestResult>> in
            // Forwards failure respose error after all automatic retries.
            return SignalProducer(value: .value(.completed(.failure(responseError))))
        }
        .take(while: { (signalTermination: SignalTermination) -> Bool in
            // Forwards values while the `.terminate` value has not been emitted.
            guard case .value(_) = signalTermination else {
                return false
            }
            return true
        }).map { (signalTermination: SignalTermination) -> RequestResult in
            guard case let .value(requestResult) = signalTermination else {
                fatalError()
            }
            return requestResult
        }
    }
    
}
