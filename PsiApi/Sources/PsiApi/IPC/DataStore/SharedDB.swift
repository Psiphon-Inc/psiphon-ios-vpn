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

/// The shared DB is a database shared between two processes.
/// More specifically, in the Psiphon iOS app, these two processes are the container and extension VPN processes.
/// Both processes can read or write data at any time, so sharing the data space must be synchronized accordingly.

public protocol SharedDBContainer {

    func setSubscriptionAuths(_ purchaseAuths: Data?)
    func getSubscriptionAuths() -> Data?

    func setContainerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber(_ seq: Int)
    func getExtensionRejectedSubscriptionAuthIdWriteSequenceNumber() -> Int

    func getRejectedSubscriptionAuthorizationIDs () -> [String]

}

public protocol SharedDBExtension {} // TODO: pending
