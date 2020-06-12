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

extension SignedAuthorization {
    
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
