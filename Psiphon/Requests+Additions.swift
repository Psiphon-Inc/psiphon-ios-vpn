/*
 * Copyright (c) 2021, Psiphon Inc.
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

extension HTTPClient {
    
    public static func `default`(urlSession: URLSession, feedbackLogger: FeedbackLogger) -> HTTPClient {
        HTTPClient(urlSession: urlSession) { (getCurrentTime, session, urlRequest, completionHandler)
            -> CancellableURLRequest in
            
            #if DEBUG || DEV_RELEASE
            let logRequest = UserDefaults.standard.bool(forKey: UserDefaultsRecordHTTP)
            let uuid = UUID()
            if logRequest {
                let requestBody: String
                if let httpBody = urlRequest.httpBody {
                    requestBody = String(data: httpBody, encoding: .utf8)!
                } else {
                    requestBody = "(nil body)"
                }
                feedbackLogger.immediate(.info, """
                    URLSessionDataTask Started: UUID: \(uuid), \
                    URL: \(String(describing: urlRequest.url?.path)), \
                    httpBody: \(requestBody)
                    """)
            }
            #endif
            
            let sessionTask = session.dataTask(with: urlRequest) { data, response, error in
                
                let result: URLSessionResult
                if let error = error {
                    // If URLSession task resulted in an error, there might be a partial response.
                    
                    #if DEBUG || DEV_RELEASE
                    if logRequest {
                        feedbackLogger.immediate(.error, """
                            URLSessionDataTask Failed: UUID: \(uuid), \
                            Error: \(SystemError<Int>.make(error as NSError))
                            """)
                        }
                    #endif
                    
                    result = URLSessionResult(
                        date: getCurrentTime(),
                        result: .failure(
                            HTTPRequestError(
                                partialResponseMetadata: (response as? HTTPURLResponse)
                                    .map(HTTPResponseMetadata.init),
                                error: SystemError<Int>.make(error as NSError)
                            )
                        )
                    )
                    
                } else {
                    // If `error` is nil, then URLSession task callback guarantees that
                    // `data` and `response` are non-nil.
                    
                    let urlResponse = (response! as! HTTPURLResponse)
                    
                    #if DEBUG || DEV_RELEASE
                    if logRequest {
                        let responseBody: String
                        if let data = data {
                            responseBody = String(data: data, encoding: .utf8)!
                        } else {
                            responseBody = "(nil data)"
                        }
                        feedbackLogger.immediate(.error, """
                            URLSessionDataTask Finished: UUID: \(uuid), \
                            Status: \(urlResponse.statusCode), \
                            Headers: \(urlResponse.allHeaderFields), \
                            Body: \(responseBody)
                            """)
                    }
                    #endif
                    
                    result = URLSessionResult(
                        date: getCurrentTime(),
                        result: .success(
                            HTTPResponseData(
                                data: data!,
                                metadata: HTTPResponseMetadata(urlResponse)
                            )
                        )
                    )
                    
                }
                completionHandler(result)
            }
            
            sessionTask.resume()
            return sessionTask
            
        }
    }
    
}
