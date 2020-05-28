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
import Testing

final class MockCancellableURLRequest: CancellableURLRequest {
    func cancel() {}
}

extension HTTPRequest {
    
    static func mockJsonRequest<Body: Encodable>(
        body: Body, method: HTTPMethod = .get, responseType: Response.Type
    ) -> Self {
        let jsonData = try! JSONEncoder().encode(body)
        return .json(url: URL(string: "https://test.psiphon.ca/")!,
                     jsonData: jsonData,
                     clientMetaData: "",
                     method: method,
                     response: responseType)
    }
    
}

final class EchoHTTPClient {
    
    var responseSequence: Generator<Result<(), HTTPRequestError>>
        = Generator(sequence: [.success(())])
    
    var responseDelay: DispatchTimeInterval = .milliseconds(0)
    var responseStatusCode = HTTPStatusCode.ok
    var requestCount: Int = 0
    var httpVersion = "HTTP/1.1"
    var headers = [String: String]()
    
    init() {}
    
    lazy var client = HTTPClient(urlSession: URLSession()) { _, _, request, completionHandler -> CancellableURLRequest in
        
        guard let httpBody = request.httpBody else {
            XCTFatal()
        }
        
        guard let httpBodyString = String(bytes: httpBody, encoding: .utf8) else {
            XCTFatal()
        }
        
        guard let url = request.url else {
            XCTFatal()
        }
        
        guard let resp = "Request:\(self.requestCount)\n\(httpBodyString)".data(using: .utf8) else {
            XCTFatal()
        }
        
        self.requestCount += 1
                    
        DispatchQueue.global().asyncAfter(deadline: .now() + self.responseDelay) {
            
            guard let response = self.responseSequence.next() else {
                XCTFatal()
            }
            
            let sessionResult: URLSessionResult = response.map { _
                -> (data: Data, response: HTTPURLResponse) in
                (data: resp,
                 response: HTTPURLResponse(
                    url: url,
                    statusCode: self.responseStatusCode.rawValue,
                    httpVersion: self.httpVersion,
                    headerFields: self.headers)!)
            }
            
            completionHandler(sessionResult)

        }
        
        return MockCancellableURLRequest()
    }
    
}

struct MockAppInfoProvider: AppInfoProvider {
    var clientPlatform: String { "" }
    
    var clientRegion: String { "" }
    
    var clientVersion: String { "" }
    
    var propagationChannelId: String { "" }
    
    var sponsorId: String { "" }
}
