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
    
    enum CodingKeys: String, CodingKey {
        case result
        case associatedValue
    }
    
    enum TagKeys: String, Codable {
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
