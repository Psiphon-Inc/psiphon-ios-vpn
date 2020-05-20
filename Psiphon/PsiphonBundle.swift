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

/// A verified stricter set of `Bundle` properties.
struct PsiphonBundle {
    let bundleIdentifier: String
    let appStoreReceiptURL: URL
    
    /// Validates app's environment give the assumptions made in the app for certain invariants to hold true.
    /// - Note: Stops program execution if any of the validations fail.
    static func from(bundle: Bundle) -> PsiphonBundle {
        return PsiphonBundle(bundleIdentifier: bundle.bundleIdentifier!,
                             appStoreReceiptURL: bundle.appStoreReceiptURL!)
    }
}
