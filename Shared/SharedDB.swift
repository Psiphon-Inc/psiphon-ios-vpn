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

/// Swift bridge for Objective-C shared DB protocol implementation.
struct SharedDBContainerObjC: PsiApi.SharedDBContainer {

    let sharedDB: PsiphonDataSharedDB

    func setSubscriptionAuths(_ purchaseAuths: Data?) {
        self.sharedDB.setSubscriptionAuths(purchaseAuths)
    }

    func getSubscriptionAuths() -> Data? {
        return self.sharedDB.getSubscriptionAuths()
    }

    func setContainerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber(_ seq: Int) {
        self.sharedDB.setContainerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber(seq)
    }

    func getExtensionRejectedSubscriptionAuthIdWriteSequenceNumber() -> Int {
        return self.sharedDB.getExtensionRejectedSubscriptionAuthIdWriteSequenceNumber()
    }

    func getRejectedSubscriptionAuthorizationIDs() -> [String] {
        self.sharedDB.getRejectedSubscriptionAuthorizationIDs()
    }

}
