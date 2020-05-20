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

extension Result: Codable where Success: Codable, Failure: Codable {
    
    private enum CodingKeys: String, CodingKey {
        case result
        case associatedValue
    }
    
    private enum TagKeys: String, Codable {
        case success
        case failure
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(TagKeys.self, forKey: .result)
        switch tag {
        case .success:
            let successValue = try container.decode(Success.self, forKey: .associatedValue)
            self = .success(successValue)
        case .failure:
            let failureValue = try container.decode(Failure.self, forKey: .associatedValue)
            self = .failure(failureValue)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success(let successValue):
            try container.encode(TagKeys.success, forKey: .result)
            try container.encode(successValue, forKey: .associatedValue)
        case .failure(let failureValue):
            try container.encode(TagKeys.failure, forKey: .result)
            try container.encode(failureValue, forKey: .associatedValue)
        }
    }
    
}

extension SubscriptionPurchaseAuthState.AuthorizationState: Codable {
    
    private enum CodingKeys: String, CodingKey {
        case state
        case requestErrorValue
        case requestRejectedReasonValue
        case authorization
    }
    
    private enum TagKeys: String, Codable {
        case notRequested
        case requestError
        case requestRejected
        case authorization
        case rejectedByPsiphon
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(TagKeys.self, forKey: .state)
        switch state {
        case .notRequested:
            self = .notRequested
        case .requestError:
            let errorEvent = try container.decode(ErrorEvent<ErrorRepr>.self,
                                                  forKey: .requestErrorValue)
            self = .requestError(errorEvent)
        case .requestRejected:
            let reason = try container.decode(RequestRejectedReason.self,
                                              forKey: .requestRejectedReasonValue)
            self = .requestRejected(reason)
        case .authorization, .rejectedByPsiphon:
            
            let base64Auth = try container.decode(String.self, forKey: .authorization)
            
            guard let base64Data = Data(base64Encoded: base64Auth) else {
                throw ErrorRepr(repr: "Failed to base64 decode value '\(base64Auth)'")
            }
            let decoder = JSONDecoder.makeRfc3339Decoder()
            let decodedAuth = try decoder.decode(SignedAuthorization.self, from: base64Data)
            let authValue = SignedData(rawData: base64Auth, decoded: decodedAuth)
            if case .authorization = state {
                self = .authorization(authValue)
            } else if case .rejectedByPsiphon = state {
                self = .rejectedByPsiphon(authValue)
            } else {
                throw ErrorRepr(repr: "Unexpected 'state' value: '\(state.rawValue)'")
            }
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notRequested:
            try container.encode(TagKeys.notRequested, forKey: .state)
        case .requestError(let errorEvent):
            try container.encode(TagKeys.requestError, forKey: .state)
            try container.encode(errorEvent, forKey: .requestErrorValue)
        case .requestRejected(let reason):
            try container.encode(TagKeys.requestRejected, forKey: .state)
            try container.encode(reason.rawValue, forKey: .requestRejectedReasonValue)
        case .authorization(let authData):
            try container.encode(TagKeys.authorization, forKey: .state)
            try container.encode(authData.rawData, forKey: .authorization)
        case .rejectedByPsiphon(let authData):
            try container.encode(TagKeys.rejectedByPsiphon, forKey: .state)
            try container.encode(authData.rawData, forKey: .authorization)
        }
    }
    
}
