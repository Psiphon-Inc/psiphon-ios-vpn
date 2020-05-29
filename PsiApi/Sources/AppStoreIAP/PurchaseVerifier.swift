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
import Utilities
import PsiApi

/// Each server endpoint should be defined as an extension
/// in a separate file (e.g. PurchaseVerifier+PsiCash.swift)
public struct PurchaseVerifierServer {

    public static func req<R>(
        url: URL,
        jsonData: Data,
        clientMetaData: ClientMetaData
    ) -> (error: NestedScopedError<ErrorRepr>?,
          request: HTTPRequest<R>) {

        var clientMetadataJSON: String = ""
        var clientMetadataError: NestedScopedError<ErrorRepr>? = .none

        switch clientMetaData.jsonString {
        case .left(let error):
            clientMetadataError =
                .some(.cons(ScopedError.init(err: ErrorRepr(repr: "client metadata error")),
                            .elem(error)))
        case .right(let jsonString):
            clientMetadataJSON = jsonString
        }

        let req = HTTPRequest.json(url: url, jsonData: jsonData,
                                clientMetaData: clientMetadataJSON,
                                method: .post, response: R.self)

        return (error: clientMetadataError, request: req)
    }

}

extension PurchaseVerifierServer {
    
    fileprivate static func psiCashUrl() -> URL {
        if Debugging.devServers {
            return PurchaseVerifierURLs.devPsiCashVerify
        } else {
            return PurchaseVerifierURLs.psiCashVerify
        }
    }

    static func psiCash(
        requestBody: PsiCashValidationRequest,
        clientMetaData: ClientMetaData
    ) -> (error: NestedScopedError<ErrorRepr>?,
        request: HTTPRequest<PsiCashValidationResponse>) {
            do {
                let encoder = JSONEncoder.makeRfc3339Encoder()
                let jsonData = try encoder.encode(requestBody)
                return PurchaseVerifierServer.req(url: PurchaseVerifierServer.psiCashUrl(),
                                                  jsonData: jsonData,
                                                  clientMetaData: clientMetaData)
            } catch {
                fatalError("failed to create request '\(error)'")
            }
    }
    
}
