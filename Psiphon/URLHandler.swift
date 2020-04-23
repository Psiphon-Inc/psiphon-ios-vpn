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
import  ReactiveSwift

struct URLHandler<T: TunnelProviderManager> {
    let open: (RestrictedURL, WeakRef<T>) -> Effect<Bool>
}

extension URLHandler {
    static func `default`<T: TunnelProviderManager>() -> URLHandler<T> {
        URLHandler<T>(
            open: { url, tpmWeakRef in
                Effect.deferred { fulfilled in
                    if Debugging.disableURLHandler {
                        fulfilled(true)
                        return
                    }
                    
                    DispatchQueue.main.async {
                        /// Due to memory pressure, the network extension is at high risk of jetsamming
                        /// before the landing page can be opened.
                        /// Tunnel status should be assessed directly (not through observables that might
                        /// introduce some latency), before opening the landing page.
                        guard let tpm = tpmWeakRef.weakRef else {
                            fulfilled(false)
                            return
                        }
                        guard let landingPage = url.getValue(tpm.connectionStatus) else {
                            fulfilled(false)
                            return
                        }
                        
                        UIApplication.shared.open(landingPage) { success in
                            fulfilled(success)
                        }
                    }
                }
        })
    }
}
