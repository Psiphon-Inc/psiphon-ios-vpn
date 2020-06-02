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
import Testing
import Utilities
import ReactiveSwift
@testable import PsiApiTestingCommon
@testable import PsiApi

struct TestRequest: Encodable {
    let value: String
}

struct RetriableTestResponse: RetriableHTTPResponse {
    
    let result: Result<String, ErrorEvent<ErrorRepr>>

    init(result: ResultType) {
        self.result = result
    }
    
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
    
    /// Every Non-200 OK response is a retriable error.
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

typealias RequestResult = RetriableTunneledHttpRequest<RetriableTestResponse>.RequestResult

func generateRetriableTunneledHttpRequestTest(
    echoHttpClient: HTTPClient,
    connectionStatusBeforeRequestSeq: [TunnelConnection.ConnectionResourceStatus],
    vpnStatusSeq: [TunnelProviderVPNStatus],
    vpnStatusSeqInterval: DispatchTimeInterval = .milliseconds(0),
    totalTimeout: TimeInterval = 1.0,
    retryCount: Int = 2,
    retryInterval: DispatchTimeInterval = .milliseconds(1),
    getCurrentTime: (() -> Date)? = nil
) -> [Signal<RequestResult, SignalProducer<RequestResult, Never>.SignalError>.Event] {
    
    let currentTimeFunc: () -> Date
    if let timeFunc = getCurrentTime {
        currentTimeFunc = timeFunc
    } else {
        currentTimeFunc = {
            return Date()
        }
    }
    
    // Arrange
    var connectionSeqGenerator = Generator(sequence: connectionStatusBeforeRequestSeq)
    
    let request = RetriableTunneledHttpRequest(
        request: HTTPRequest.mockJsonRequest(
            body: TestRequest(value: "request test data"),
            responseType: RetriableTestResponse.self),
        retryCount: retryCount,
        retryInterval: retryInterval
    )

    let connectedConnection = TunnelConnection {
        guard let value = connectionSeqGenerator.next() else {
            XCTFatal()
        }
        return value
    }

    // Act
    let result = request.callAsFunction(
        getCurrentTime: currentTimeFunc,
        tunnelStatusSignal: SignalProducer.just(
            values: vpnStatusSeq,
            withInterval: vpnStatusSeqInterval
        ).concat(.never),
        tunnelConnectionRefSignal: SignalProducer.neverComplete(value: connectedConnection),
        httpClient: echoHttpClient
    ).collectForTesting(timeout: totalTimeout)

    XCTAssert(connectionSeqGenerator.exhausted)
    
    return result
}


final class RequestsTests: XCTestCase {
    
    var echoHttpClient: EchoHTTPClient!
    
    override func setUpWithError() throws {
        Debugging = .disabled()
        echoHttpClient = EchoHTTPClient()
    }
    
    override func tearDownWithError() throws {
        echoHttpClient = nil
    }
    
    func testTunneled200OKRequest() {
        // Arrange
        let request = RetriableTunneledHttpRequest(
            request: HTTPRequest.mockJsonRequest(
                body: TestRequest(value: "request test data"),
                responseType: RetriableTestResponse.self)
        )
        
        let connectedConnection = TunnelConnection {
            .connection(.connected)
        }
        
        // Act
        let result = request.callAsFunction(
            getCurrentTime: { Date() },
            tunnelStatusSignal: SignalProducer.neverComplete(value: .connected),
            tunnelConnectionRefSignal: SignalProducer.neverComplete(value: connectedConnection),
            httpClient: echoHttpClient.client
        ).collectForTesting(timeout: 1.0)
        
        // Assert
        XCTAssert(
            result == [
                .value(.completed(.success(#"Request:0\#n{"value":"request test data"}"#))),
                .completed],
            "Got result '\(result)'"
        )
    }
    
    func testConnectedNilTunnelManager() {
        // Act
        let result = generateRetriableTunneledHttpRequestTest(
            echoHttpClient: self.echoHttpClient.client,
            connectionStatusBeforeRequestSeq: [ .resourceReleased ],
            vpnStatusSeq: [ .connected ]
        )
        
        // Assert
        XCTAssert(
            result == [
                .value(.willRetry(.whenResolved(tunnelError: .nilTunnelProviderManager))),
                .failed(.signalTimedOut)],
            "Got result '\(result)'"
        )
        
        XCTAssert(self.echoHttpClient.requestCount == 0)
    }
    
    func testRetryAfterNewTunnelManager() {
        // Act
        let result = generateRetriableTunneledHttpRequestTest(
            echoHttpClient: self.echoHttpClient.client,
            connectionStatusBeforeRequestSeq: [
                .resourceReleased,
                .resourceReleased,
                .connection(.connected)
            ],
            vpnStatusSeq: [
                .connected,
                .disconnected,
                .connected,
                .connecting,
                .connected
            ]
        )
        
        // Assert
        XCTAssert(
            result == [.value(.willRetry(.whenResolved(tunnelError: .nilTunnelProviderManager))),
                 .value(.willRetry(.whenResolved(tunnelError: .tunnelNotConnected))),
                 .value(.willRetry(.whenResolved(tunnelError: .nilTunnelProviderManager))),
                 .value(.willRetry(.whenResolved(tunnelError: .tunnelNotConnected))),
                 .value(.completed(.success(#"Request:0\#n{"value":"request test data"}"#))),
                 .completed],
            "Got result '\(result)'"
        )
        
        XCTAssert(self.echoHttpClient.requestCount == 1)
    }
    
    func testConnectedThenQuickJetsamRace() {
        // Tests tunnel being initially connected at the time of the request,
        // and quickly disconnected (e.g. jetsam) just after the request is made.
        
        // Arrange
        echoHttpClient.responseDelay = .milliseconds(10)
        
        // Act
        let result = generateRetriableTunneledHttpRequestTest(
            echoHttpClient: self.echoHttpClient.client,
            connectionStatusBeforeRequestSeq: [.connection(.connected)],
            vpnStatusSeq: [
                .connected,
                .disconnected
            ],
            vpnStatusSeqInterval: .milliseconds(1)
        )
        
        // Assert
        XCTAssert(
            result == [
                .value(.willRetry(.whenResolved(tunnelError: .tunnelNotConnected))),
                .failed(.signalTimedOut)],
            "Got result '\(result)'"
        )
        
        XCTAssert(self.echoHttpClient.requestCount == 1)
    }
    
    func testConnectedThenDelayedJetsamRace() {
        // Tests tunnel being initially connected at the time of the request,
        // and then disconnected (e.g. jetsam) after response is received from server.
        
        // Act
        let result = generateRetriableTunneledHttpRequestTest(
            echoHttpClient: self.echoHttpClient.client,
            connectionStatusBeforeRequestSeq: [.connection(.connected)],
            vpnStatusSeq: [
                .connected,
                .disconnected
            ],
            vpnStatusSeqInterval: .milliseconds(10)
        )
        
        // Assert
        XCTAssert(self.echoHttpClient.responseDelay == .milliseconds(0))
        
        XCTAssert(
            result == [.value(.completed(.success(#"Request:0\#n{"value":"request test data"}"#))),
                 .completed],
            "Got result '\(result)'"
        )
        
        XCTAssert(self.echoHttpClient.requestCount == 1)
    }
    
    func testShowcaseDoubleRequest() {
        // This is more of a showcase of the condition that can cause two requests
        // to be sent to server due to quick disconnected event.
        
        // Arrange
        self.echoHttpClient.responseDelay = .milliseconds(10)
        self.echoHttpClient.responseSequence = Generator(sequence:
            [.success(()), .success(())]
        )
        
        // Act
        let result = generateRetriableTunneledHttpRequestTest(
            echoHttpClient: self.echoHttpClient.client,
            connectionStatusBeforeRequestSeq: [
                .connection(.connected),
                .connection(.connected)
            ],
            vpnStatusSeq: [
                .connected,
                .disconnected,
                .connected,
                .disconnected
            ],
            vpnStatusSeqInterval: .milliseconds(0)
        )
        
        // Assert
        XCTAssert(self.echoHttpClient.responseDelay == .milliseconds(10))
        
        XCTAssert(
            result == [
                .value(.willRetry(.whenResolved(tunnelError: .tunnelNotConnected))),
                .value(.willRetry(.whenResolved(tunnelError: .tunnelNotConnected))),
                .failed(.signalTimedOut)
            ],
            "Got result '\(result)'"
        )
        
        XCTAssert(self.echoHttpClient.requestCount == 2)
        
        XCTAssert(self.echoHttpClient.responseSequence.exhausted)
    }
    
    func testDisconnectedToConnected() {
        // Tests requesting not going through due to tunnel status signal emitting disconnected,
        // and then tunnel disconnecting, just before the request is made,
        // and then tunnel status signal emitting disconnected once again before
        // the tunnel is connected and request is sent successfully.
        
        // Arrange
        self.echoHttpClient.responseDelay = .milliseconds(10)
        
        // Act
        let result = generateRetriableTunneledHttpRequestTest(
            echoHttpClient: self.echoHttpClient.client,
            connectionStatusBeforeRequestSeq: [
                .connection(.disconnected),
                .connection(.connected)
            ],
            vpnStatusSeq: [
                .disconnected,
                .connected,
                .disconnected,
                .connected,
            ]
        )
        
        // Assert
        XCTAssert(self.echoHttpClient.responseDelay == .milliseconds(10))
        
        XCTAssert(
            result == [
                .value(.willRetry(.whenResolved(tunnelError: .tunnelNotConnected))),
                .value(.willRetry(.whenResolved(tunnelError: .tunnelNotConnected))),
                .value(.willRetry(.whenResolved(tunnelError: .tunnelNotConnected))),
                .value(.completed(.success(#"Request:0\#n{"value":"request test data"}"#))),
                .completed],
            "Got result '\(result)'"
        )
        
        XCTAssert(self.echoHttpClient.requestCount == 1)
    }
    
    func testRetryWithHttpStatusError() {
        
        // Arrange
        let errorDate = Date()
        
        let responseErrorEvent = ErrorEvent(ErrorRepr(repr: "request error"), date: errorDate)
        
        let expectedResponse = RetriableTestResponse(result: .failure(responseErrorEvent))
                
        let httpClientError = ErrorEvent(SystemError.arbitrary.generate, date: errorDate)
        
        // HTTPClient error date should match expected response error date.
        self.echoHttpClient.responseSequence = Generator(sequence:
            [.failure(HTTPRequestError(partialResponse: nil, errorEvent: httpClientError)),
             .failure(HTTPRequestError(partialResponse: nil, errorEvent: httpClientError)),
             .failure(HTTPRequestError(partialResponse: nil, errorEvent: httpClientError))]
        )
        
        let retryInterval = DispatchTimeInterval.milliseconds(1)
        
        // Act
        let result = generateRetriableTunneledHttpRequestTest(
            echoHttpClient: self.echoHttpClient.client,
            connectionStatusBeforeRequestSeq: [
                .connection(.connected),
                .connection(.connected), // Retry 1
                .connection(.connected)  // Retry 2
            ],
            vpnStatusSeq: [ .connected ],
            retryCount: 2,
            retryInterval: retryInterval,
            getCurrentTime: {
                XCTFatal(message: "getCurrentTime should not be called")
            }
        )
        
        // Assert
        
        // Checks that every error result is a retriable error for `RetriableTestResponse`.
        let errorEvent = ErrorEvent(ErrorRepr(repr: "error"))
        let resultTuple = RetriableTestResponse.unpackRetriableResultError(.failure(errorEvent))
        XCTAssert(resultTuple.retryDueToError == errorEvent)
        
        XCTAssert(
            result ==
                [.value(.willRetry(.afterTimeInterval(
                    interval: retryInterval, result: expectedResponse.result))),
                 .value(.willRetry(.afterTimeInterval(
                    interval: retryInterval, result: expectedResponse.result))),
                 .value(.willRetry(.afterTimeInterval(
                    interval: retryInterval, result: expectedResponse.result))),
                 .value(.failed(responseErrorEvent)),
                 .completed],
            "Got result '\(result)'"
        )
        
        XCTAssert(self.echoHttpClient.requestCount == 3)
        
        XCTAssert(self.echoHttpClient.responseSequence.exhausted)
    }
    
    func testRetryWithHttpStatusErrorThenSuccess() {
        
        // Arrange
        let errorDate = Date()
        
        let responseErrorEvent = ErrorEvent(ErrorRepr(repr: "request error"), date: errorDate)
        
        let expectedResponse = RetriableTestResponse(result: .failure(responseErrorEvent))
                
        let httpClientError = ErrorEvent(SystemError.arbitrary.generate, date: errorDate)
        
        // HTTPClient error date should match expected response error date.
        self.echoHttpClient.responseSequence = Generator(sequence:
            [.failure(HTTPRequestError(partialResponse: nil, errorEvent: httpClientError)),
             .success(())]
        )
        
        let retryInterval = DispatchTimeInterval.milliseconds(1)
        
        // Act
        let result = generateRetriableTunneledHttpRequestTest(
            echoHttpClient: self.echoHttpClient.client,
            connectionStatusBeforeRequestSeq: [
                .connection(.connected),
                .connection(.connected), // Retry 1
            ],
            vpnStatusSeq: [ .connected ],
            retryCount: 2,
            retryInterval: retryInterval,
            getCurrentTime: {
                XCTFatal(message: "getCurrentTime should not be called")
            }
        )
        
        // Assert
        
        // Checks that every error result is a retriable error for `RetriableTestResponse`.
        let errorEvent = ErrorEvent(ErrorRepr(repr: "error"))
        let resultTuple = RetriableTestResponse.unpackRetriableResultError(.failure(errorEvent))
        XCTAssert(resultTuple.retryDueToError == errorEvent)
        
        XCTAssert(
            result == [
                .value(.willRetry(.afterTimeInterval(
                    interval: retryInterval, result: expectedResponse.result))),
                .value(.completed(.success(#"Request:1\#n{"value":"request test data"}"#))),
                .completed],
            "Got result '\(result)'"
        )
        
        XCTAssert(self.echoHttpClient.requestCount == 2)
        
        XCTAssert(self.echoHttpClient.responseSequence.exhausted)
    }
    
    static var allTests = [
        ("testRetryWithHttpStatusErrorThenSuccess", testRetryWithHttpStatusErrorThenSuccess),
    ]
    
}
