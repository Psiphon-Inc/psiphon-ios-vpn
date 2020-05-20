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

import XCTest
import ReactiveSwift
import NetworkExtension
@testable import Psiphon

final class MockCancellableURLRequest: CancellableURLRequest {
    func cancel() {}
}

extension HTTPRequest {
    
    static func jsonMock<Body: Encodable>(
        body: Body, method: HTTPMethod = .get, responseType: Response.Type
    ) -> Self {
        .json(url: URL(string: "https://test.psiphon.ca/")!,
              body: body,
              clientMetaData: "",
              method: method,
              response: responseType)
    }
    
}

struct TestRequest: Encodable {
    let value: String
}

struct RetriableTestResponse: RetriableHTTPResponse {
    
    let result: Result<String, ErrorEvent<ErrorRepr>>

    init(urlSessionResult: URLSessionResult) {
        switch urlSessionResult {
        case let .success((dataBytes, urlResponse)):
            let data = String(bytes: dataBytes, encoding: .utf8)!
            switch urlResponse.typedStatusCode {
            case .ok:
                self.result = .success(data)
            default:
                self.result = .failure(ErrorEvent(ErrorRepr(
                    repr: "status code: '\(urlResponse.statusCode)' data: '\(data)'"
                )))
            }
        case let .failure(requestError):
            self.result = .failure(requestError.errorEvent.map { _ in
                ErrorRepr(repr: "request error")
            })
        }
    }
    
    static func unpackRetriableResultError(
        _ result: ResultType
    ) -> (result: ResultType, retryDueToError: FailureEvent?) {
        switch result {
        case .success(_):
            return (result: result, retryDueToError: nil)
            
        case .failure(let failureEvent):
            return (result: result, retryDueToError: failureEvent)
        }
    }
    
}

final class RequestsTest: XCTestCase {
    
    var httpRequestNum: Int = 0
    var echoHttpClient: HTTPClient!
    
    override func setUpWithError() throws {
        Debugging = .disabled()
        
        echoHttpClient = HTTPClient { _, request, completionHandler -> CancellableURLRequest in
            
            guard let httpBody = request.httpBody else {
                XCTFatal()
            }
            
            guard let httpBodyString = String(bytes: httpBody, encoding: .utf8) else {
                XCTFatal()
            }
            
            guard let url = request.url else {
                XCTFatal()
            }
            
            guard let resp = "\(self.httpRequestNum)\n\(httpBodyString)".data(using: .utf8) else {
                XCTFatal()
            }
            
            self.httpRequestNum += 1
                        
            completionHandler(.success(
                (data: resp,
                 response: HTTPURLResponse(
                    url: url,
                    statusCode: HTTPStatusCode.ok.rawValue,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil)!)))
            
            return MockCancellableURLRequest()
        }
    }
    
    override func tearDownWithError() throws {
        echoHttpClient = nil
        httpRequestNum = 0
    }
    
    func testTunneled200OKRequest() {
        // Arrange
        let request = RetriableTunneledHttpRequest(
            request: HTTPRequest.jsonMock(
                body: TestRequest(value: "request test data"),
                responseType: RetriableTestResponse.self)
        )
        
        let connectedConnection = TunnelConnection {
            .connection(.connected)
        }
        
        let connectedIntent = VPNStatusWithIntent(
            status: .connected,
            intent: .start(transition: .none)
        )
        
        // Act
        let result = request.callAsFunction(
            tunnelStatusWithIntentSignal: SignalProducer(value: connectedIntent),
            tunnelConnectionRefSignal: SignalProducer(value: connectedConnection),
            httpClient: echoHttpClient
        ).collectForTesting(timeout: 1.0)
        
        // Assert
        XCTAssert(
            result.isEqual(
                [.value(.completed(.success(#"0\#n{"value":"request test data"}"#))), .completed]
            ),
            "Got result '\(result)'"
        )
    }
    
}
