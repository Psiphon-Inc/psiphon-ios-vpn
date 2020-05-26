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
import Utilities

protocol AppInfoProvider : Encodable {
    var clientPlatform : String { get }
    var clientRegion : String { get }
    var clientVersion : String { get }
    var propagationChannelId : String { get }
    var sponsorId : String { get }
}

struct ClientMetaData: Encodable {

    let clientPlatform : String
    let clientRegion : String
    let clientVersion : String
    let propagationChannelId : String
    let sponsorId : String

    private enum CodingKeys: String, CodingKey {
        case clientPlatform = "client_platform"
        case clientRegion = "client_region"
        case clientVersion = "client_version"
        case propagationChannelId = "propagation_channel_id"
        case sponsorId = "sponsor_id"
    }

    init(_ appInfo : AppInfoProvider) {
        self.clientPlatform = appInfo.clientPlatform
        self.clientRegion = appInfo.clientRegion
        self.clientVersion = appInfo.clientVersion
        self.propagationChannelId = appInfo.propagationChannelId
        self.sponsorId = appInfo.sponsorId
    }

    var jsonString: Either<ScopedError<ErrorRepr>, String> {
        do {
            let jsonData = try JSONEncoder().encode(self)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return .right(jsonString)
            }
            return
                .left(
                    ScopedError(err:
                        ErrorRepr(repr: "failed to encode ClientMetaData as utf8 string")))
        } catch {
            return
                .left(
                    ScopedError(err:
                        ErrorRepr(repr: error.localizedDescription)))
        }
    }
    
}
