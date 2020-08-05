/*
* Copyright (c) 2019, Psiphon Inc.
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

func plistReader<DecodeType: Decodable>(key: String, toType: DecodeType.Type) throws -> DecodeType {
    // TODO: Add bundle dependency as an argument.
    guard let url = Bundle.main.url(forResource: key, withExtension: "plist") else {
        fatalError("'\(key).plist' is not valid")
    }

    let data = try Data(contentsOf: url)
    let decoder = PropertyListDecoder()
    return try decoder.decode(toType, from: data)
}

extension URL {
    
    func isEqualInSchemeAndHost(to other: URL) -> Bool {
        self.scheme == other.scheme && self.host == other.host
    }
    
}
