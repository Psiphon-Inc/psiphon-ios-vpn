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
import SwiftCheck
@testable import PsiApi

extension TunnelConnection: Arbitrary {
    public static var arbitrary: Gen<TunnelConnection> {
        ConnectionResourceStatus.arbitrary.map{ cxn in
            TunnelConnection {
                cxn
            }
        }
    }
}

extension TunnelProviderVPNStatus : Arbitrary {
    public static var arbitrary: Gen<TunnelProviderVPNStatus> {
        Gen.one(of: [
            // Should cover all cases.
            Gen.pure(.invalid),
            Gen.pure(.connecting),
            Gen.pure(.connected),
            Gen.pure(.reasserting),
            Gen.pure(.disconnecting)
        ])
    }
}

extension TunnelConnection.ConnectionResourceStatus : Arbitrary {
    public static var arbitrary: Gen<TunnelConnection.ConnectionResourceStatus> {
        Gen.one(of: [
            // Should cover all cases
            Gen.pure(.resourceReleased),
            TunnelProviderVPNStatus.arbitrary.map(
                TunnelConnection.ConnectionResourceStatus.connection
            )
        ])
    }
}
