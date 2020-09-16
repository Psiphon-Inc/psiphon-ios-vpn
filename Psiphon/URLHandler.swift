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
import ReactiveSwift
import PsiApi

struct URLHandler {
    let open: (URL, TunnelConnection, MainDispatcher) -> Effect<Bool>
}

extension URLHandler {
    static func `default`() -> URLHandler {
        URLHandler(
            open: { url, tunnelConnection, mainDispatcher in
                Effect.deferred(dispatcher: mainDispatcher) { fulfilled in
                    if Debugging.disableURLHandler {
                        fulfilled(true)
                        return
                    }
                    
                    /// Due to memory pressure, the network extension is at high risk of jetsamming
                    /// before the landing page can be opened.
                    /// Tunnel status should be assessed directly (not through observables that might
                    /// introduce some latency), before opening the landing page.
                    switch tunnelConnection.connectionStatus() {
                    case .connection(.connected):
                        UIApplication.shared.open(url) { success in
                            fulfilled(success)
                        }
                    default:
                        fulfilled(false)
                        return
                    }
                }
        })
    }
}
