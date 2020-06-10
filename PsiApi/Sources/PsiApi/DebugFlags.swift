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

#if DEBUG
public var Debugging = DebugFlags()
#else
public var Debugging = DebugFlags.disabled()
#endif

public struct DebugFlags {
    public var mainThreadChecks = true
    public var disableURLHandler = false
    public var devServers = true
    public var ignoreTunneledChecks = false
    public var disableConnectOnDemand = false
    
    public var printStoreLogs = false
    public var printAppState = false
    public var printHttpRequests = true
    
    public static func disabled() -> Self {
        return .init(mainThreadChecks: false,
                     disableURLHandler: false,
                     devServers: false,
                     ignoreTunneledChecks: false,
                     disableConnectOnDemand: false,
                     printStoreLogs: false,
                     printAppState: false,
                     printHttpRequests: false)
    }
}
