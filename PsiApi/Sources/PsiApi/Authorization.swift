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

public typealias AuthorizationID = String

public struct SignedAuthorization: Hashable, Codable {
    public let authorization: Authorization
    public let signingKeyID: String
    public let signature: String
    
    public init(authorization: Authorization, signingKeyID: String, signature: String) {
        self.authorization = authorization
        self.signingKeyID = signingKeyID
        self.signature = signature
    }
    
    enum CodingKeys: String, CodingKey {
        case authorization = "Authorization"
        case signingKeyID = "SigningKeyID"
        case signature = "Signature"
    }
}

extension SignedAuthorization: CustomFieldFeedbackDescription {
    
    public var feedbackFields: [String : CustomStringConvertible] {
        ["ID": authorization.id,
         "Expires": authorization.expires,
         "AccessType": authorization.accessType.rawValue]
    }
    
}

public struct Authorization: Hashable, Codable {
    public let id: AuthorizationID
    public let accessType: AccessType
    public let expires: Date
    
    public enum AccessType: String, Codable, CaseIterable {
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
    
    public func hash(into hasher: inout Hasher) {
        // Authorization ID is unique.
        hasher.combine(self.id)
    }
    
}

/// `SignedData` is a wrapper around signed decodable data returned by a server(e.g. base64 encoded
/// `SignedAuthorization` string returned as part of purchase verifier's server response),
/// that also holds the original raw value.
/// This struct is useful when the raw value needs to be preserved, where there
/// might be potential data change from encodings/decodings. (e.g. a `Date` encoded value
/// might slightly differ from the value from the server)
public struct SignedData<Decoded: Decodable & CustomStringConvertible>: Hashable, CustomStringConvertible {

    public let rawData: String
    public let decoded: Decoded
    
    public init(rawData: String, decoded: Decoded) {
        self.rawData = rawData
        self.decoded = decoded
    }
    
    public static func == (lhs: SignedData<Decoded>, rhs: SignedData<Decoded>) -> Bool {
        lhs.rawData == rhs.rawData
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawData)
    }
    
    /// `rawData` is treated as a secret value and not included in the description.
    public var description: String {
        return decoded.description
    }
    
}
