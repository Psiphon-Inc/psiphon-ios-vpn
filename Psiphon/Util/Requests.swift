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

/// A success case neabs that the HTTP request succeeded and server returned a response,
/// the response from the server might itself contain an error.
typealias URLSessionResult = Result<(data: Data, response: HTTPURLResponse), HTTPRequestError>

protocol HTTPHeader {
    static var headerKey: String { get }
}

protocol HTTPResponse {
    associatedtype Success
    associatedtype Failure: HashableError
    typealias FailureEvent = ErrorEvent<Failure>

    var result: Result<Success, FailureEvent> { get }

    init(urlSessionResult: URLSessionResult)
}

struct HTTPRequest<Response: HTTPResponse> {
    let urlRequest: URLRequest
    let responseType: Response.Type

    init(url: URL, body: Data?, clientMetaData: String, method: HTTPMethod, contentType: HTTPContentType,
         response: Response.Type) {
        var request = URLRequest(url: url,
                                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                timeoutInterval: 60.0)
        request.httpBody = body
        request.httpMethod = method.rawValue
        request.setValue(contentType.rawValue, forHTTPHeaderField: HTTPContentType.headerKey)
        request.setValue(clientMetaData, forHTTPHeaderField: VerifierRequestMetadataHttpHeaderField)

        if Debugging.printHttpRequests {
            request.debugPrint()
        }

        self.urlRequest = request
        self.responseType = response
    }

    static func json<Body: Encodable>(
        url: URL, body: Body, clientMetaData: String, method: HTTPMethod, response: Response.Type
    ) -> Self? {
        let jsonData: Data
        do {
            try jsonData = JSONEncoder().encode(body)
        } catch {
            PsiFeedbackLogger.error(withType: "Requests",
                                    message: "failed to serialize data",
                                    object: error)
            return  nil
        }

        return .init(url: url, body: jsonData, clientMetaData: clientMetaData,
                     method: method, contentType: .json, response: response)
    }

}

struct HTTPRequestError: Error {
    /// If a response from the server is received, regardless of whether the request
    /// completes successfully or fails, the response parameter contains that information.
    /// From: https://developer.apple.com/documentation/foundation/urlsession/1410330-datatask
    let partialResponse: HTTPURLResponse?
    let errorEvent: ErrorEvent<SystemError>
}

fileprivate func request<Response>(
    _ requestData: HTTPRequest<Response>,
    handler: @escaping (Response) -> Void
) -> URLSessionTask {
    let config = URLSessionConfiguration.ephemeral
    let session = URLSession(configuration: config).dataTask(with: requestData.urlRequest)
    { data, response, error in
        let result: URLSessionResult
        if let error = error {
            result = .failure(HTTPRequestError(partialResponse: response as? HTTPURLResponse,
                                               errorEvent: ErrorEvent(error as SystemError)))
        } else {
            result = .success((data: data!, response: response! as! HTTPURLResponse))
        }
        handler(Response(urlSessionResult: result))
    }
    session.resume()
    return session
}

func httpRequest<Response>(
    request urlRequest: HTTPRequest<Response>
) -> Effect<Response> {
    return SignalProducer { observer, lifetime in
        let session = request(urlRequest) { response in
            observer.fulfill(value: response)
        }
        lifetime.observeEnded {
            session.cancel()
        }
    }
}
