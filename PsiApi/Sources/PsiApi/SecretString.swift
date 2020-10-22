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

/// Represents a secret string, that is safe for logging.
/// Note that `SecretString` type does not provide any security guarantees,
/// and is meant to signify to the programmer that this value contains a secret that
/// should be handled carefully.
public struct SecretString: CustomDebugStringConvertible,
                            CustomStringConvertible,
                            CustomReflectable {
    
    public var description: String {
        "[redacted]"
    }
    
    public var debugDescription: String {
        description
    }
    
    public var customMirror: Mirror {
        Mirror(reflecting: description)
    }
    
    private let storage: String
    
    public var isEmpty: Bool {
        storage.isEmpty
    }
    
    public init(_ value: String) {
        self.storage = value
    }
    
    /// Divulges contained secret as a `String`.
    public func unsafeMap<B>(_ f: (String) -> B) -> B {
        f(storage)
    }
    
}
