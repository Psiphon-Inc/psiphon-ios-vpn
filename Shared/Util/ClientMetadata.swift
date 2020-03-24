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

let VerifierRequestMetadataHttpHeaderField = "X-Verifier-Metadata"

struct ClientMetaData: Encodable {
    let clientPlatform: String = AppInfo.clientPlatform()
    let clientRegion: String = AppInfo.clientRegion() ?? ""
    let clientVersion: String = AppInfo.appVersion() ?? ""
    let propagationChannelID: String = AppInfo.propagationChannelId() ?? ""
    let sponsorID: String = AppInfo.sponsorId() ?? ""

    private enum CodingKeys: String, CodingKey {
        case clientPlatform = "client_platform"
        case clientRegion = "client_region"
        case clientVersion = "client_version"
        case propagationChannelID = "propagation_channel_id"
        case sponsorID = "sponsor_id"
    }

    lazy var jsonString: String = {
        do {
            let jsonData = try JSONEncoder().encode(ClientMetaData())
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            PsiFeedbackLogger.error(withType: "ClientMetaData",
                                    message: "failed to serialize client metadata",
                                    object: error)
        }
        return ""
    }()
}

@objc class ObjCClientMetaData: NSObject {
    @objc class func httpHeaderField() -> String {
        return VerifierRequestMetadataHttpHeaderField
    }

    @objc class func jsonString() -> String {
        var clientMetaData = ClientMetaData()
        return clientMetaData.jsonString
    }
}
