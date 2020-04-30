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

/// Authorization JSON representation
/// ```
/// {
///   "Authorization" : {
///      "ID" : <derived unique ID>,
///      "AccessType" : <access type name; e.g., "my-access">,
///      "Expires" : <RFC3339-encoded UTC time value>
///   },
///   "SigningKeyID" : <unique key ID>,
///   "Signature" : <Ed25519 digital signature>
/// }
/// ```
///

typealias AuthorizationID = String

struct SignedAuthorization: Hashable, Codable {
    let authorization: Authorization
    let signingKeyID: String
    let signature: String
    
    enum CodingKeys: String, CodingKey {
        case authorization = "Authorization"
        case signingKeyID = "SigningKeyID"
        case signature = "Signature"
    }
}

extension SignedAuthorization {
    
    func base64String() throws -> String {
        let encoder = JSONEncoder.makeRfc3339Encoder()
        let result = try encoder.encode(self)
        return result.base64EncodedString()
    }
    
    static func make(base64String: String) throws -> Self? {
        guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            return nil
        }
        let decoder = JSONDecoder.makeRfc3339Decoder()
        return try decoder.decode(Self.self, from: data)
    }
    
    static func make(setOfBase64Strings: [String]) -> Set<SignedAuthorization> {
        Set(setOfBase64Strings.compactMap {
            return try? SignedAuthorization.make(base64String: $0)
        })
    }
    
}

struct Authorization: Hashable, Codable {
    let id: AuthorizationID
    let accessType: AccessType
    let expires: Date
    
    enum AccessType: String, Codable {
        case appleSubscription = "apple-subscription"
        case appleSubscriptionTest = "apple-subscription-test"
        case speedBoost = "speed-boost"
        case speedBoostTest = "speed-boost-test"
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case accessType = "AccessType"
        case expires = "Expires"
    }
    
    func hash(into hasher: inout Hasher) {
        // Authorization ID is unique.
        hasher.combine(self.id)
    }
    
}
