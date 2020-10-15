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

public extension Result {

    var isSuccess: Bool {
        switch self {
        case .success(_): return true
        case .failure(_): return false
        }
    }
    
    var isFailure: Bool {
        !isSuccess
    }
    
    func successToOptional() -> Success? {
        switch self {
        case .success(let value):
            return value
        case .failure(_):
            return .none
        }
    }

    func failureToOptional() -> Failure? {
        switch self {
        case .success:
            return .none
        case .failure(let error):
            return error
        }
    }
    
    func successToUnit() -> Result<(), Failure> {
        switch self {
        case .success(_):
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func biFlatMap<C, D: Error>(
        transformSuccess: (Success) -> Result<C, D>,
        transformFailure: (Failure) -> Result<C, D>
    ) -> Result<C, D> {
        switch self {
        case let .success(success):
            return transformSuccess(success)
        case let .failure(error):
            return transformFailure(error)
        }
    }
    
}

public extension Result where Success == () {
    
    func toUnit() -> Result<Unit, Failure> {
        self.map { _ in
            .unit
        }
    }

}
