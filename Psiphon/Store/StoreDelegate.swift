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

class ObjCDelegate: NSObject {}

class StoreDelegate<Action>: ObjCDelegate {
    
    /// Delegates typically return their result on a global concurrent dispatch queue.
    /// To avoid `store.send` accidentally being called from outside the main dispatch queue,
    /// we therefore hide access to store object and provide a `sendOnMain` function.
    private let store: Store<Unit, Action>
    
    init(store: Store<Unit, Action>) {
        self.store = store
    }
    
    func sendOnMain(_ action: Action) {
        DispatchQueue.main.async { [unowned self] in
            self.store.send(action)
        }
    }
    
}
