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
import Utilities

open class ObjCDelegate: NSObject {}

/// `StoreDelegate` is a convenience class meant to be sub-classed by classes that are delegates
/// of some object.
/// Delegate callbacks can call `storeSend(_:)` to send actions to the `store` object.
open class StoreDelegate<Action>: ObjCDelegate {
    
    /// Delegates typically return their result on a global concurrent dispatch queue.
    private let store: Store<Utilities.Unit, Action>
    
    public init(store: Store<Utilities.Unit, Action>) {
        self.store = store
    }
    
    /// Sends action to `store` object this delegate is initialized with.
    /// This function is thread-safe.
    public func storeSend(_ action: Action) {
        self.store.send(action)
    }
    
}
