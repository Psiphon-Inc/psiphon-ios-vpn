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

public extension Optional {
    
    /// If has some value then produces a success, otherwise produces a failure with the given lazy value.
    func optionalToSuccess<Failure: Error>(
        failure: @autoclosure () -> Failure
    ) -> Result<Wrapped, Failure> {
        switch self {
        case .none:
            return .failure(failure())
        case .some(let wrapped):
            return .success(wrapped)
        }
    }
    
}

public extension Optional where Wrapped: Error {
    
    /// If has some value then produces a failure, otherwise produces a success with the given lazy value.
    func optionalToFailure<Success>(
        success: @autoclosure () -> Success
    ) -> Result<Success, Wrapped> {
        switch self {
        case .none:
            return .success(success())
        case .some(let wrappedError):
            return .failure(wrappedError)
        }
    }
    
}
