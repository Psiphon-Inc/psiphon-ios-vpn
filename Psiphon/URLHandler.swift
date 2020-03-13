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

struct URLHandler {
    let open: (RestrictedURL) -> Effect<Bool>
}

extension URLHandler {
    static let `default` = URLHandler(
        open: { url in
            Effect { observer, _ in
                if Debugging.disableURLHandler {
                    observer.fulfill(value: true)
                    return
                }
                /// Due to memory pressure, the network extension is at high risk of jetsamming before the landing page can be opened.
                /// Tunnel status should be assessed directly (not through observables that might introduce some latency),
                /// before opening the landing page.
                guard let landingPage = url.getValue(Current) else {
                    observer.fulfill(value: false)
                    return
                }

                DispatchQueue.main.async {
                    UIApplication.shared.open(landingPage) { success in
                        observer.fulfill(value: success)
                    }
                }
            }
    })
}
