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
import Promises
import ReactiveSwift

struct PurchaseVerifierServerEndpoints {

    private enum EndpointURL {
        case subscription
        case psiCash

        var url: URL {
            switch self {
            case .subscription:
                if Debugging.devServers {
                    return PurchaseVerifierURLs.devSubscriptionVerify
                } else {
                    return PurchaseVerifierURLs.subscriptionVerify
                }
            case .psiCash:
                if Debugging.devServers {
                    return PurchaseVerifierURLs.devPsiCashVerify
                } else {
                    return PurchaseVerifierURLs.psiCashVerify
                }
            }
        }
    }
    
    static func subscription(
        requestBody: SubscriptionValidationRequest,
        clientMetaData: ClientMetaData
    ) -> HTTPRequest<SubscriptionValidationResponse> {
        return HTTPRequest.json(url: EndpointURL.subscription.url, body: requestBody,
                                clientMetaData: clientMetaData.jsonString,
                                method: .post, response: SubscriptionValidationResponse.self)
    }

    static func psiCash(
        requestBody: PsiCashValidationRequest,
        clientMetaData: ClientMetaData
    ) -> HTTPRequest<PsiCashValidationResponse> {
        return HTTPRequest.json(url: EndpointURL.psiCash.url, body: requestBody,
                                clientMetaData: clientMetaData.jsonString,
                                method: .post, response: PsiCashValidationResponse.self)
    }
}
