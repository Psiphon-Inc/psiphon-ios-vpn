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
import PsiApi

class MutableDBContainer {
    var subscriptionAuths: Data?
    var containerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber: Int

    init(subscriptionAuths: Data?, containerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber: Int) {
        self.subscriptionAuths = subscriptionAuths
        self.containerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber = containerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber
    }
}
 
struct TestSharedDBContainer: SharedDBContainer {

    let state: MutableDBContainer

    func setSubscriptionAuths(_ purchaseAuths: Data?) {
        self.state.subscriptionAuths = purchaseAuths
    }

    func getSubscriptionAuths() -> Data? {
        return self.state.subscriptionAuths
    }

    func setContainerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber(_ seq: Int) {
        self.state.containerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber = seq
    }

    func getExtensionRejectedSubscriptionAuthIdWriteSequenceNumber() -> Int {
        return self.state.containerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber
    }

    func getRejectedSubscriptionAuthorizationIDs() -> [String] {
        // TODO: in the future random auth IDs should be rejected or
        // all auth IDs except the latest one.
        return []
    }
}
