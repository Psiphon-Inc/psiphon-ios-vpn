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
import SwiftCheck
@testable import PsiApi
@testable import AppStoreIAP

extension SubscriptionReducerState: Arbitrary {
    public static var arbitrary: Gen<SubscriptionReducerState> {
        Gen.compose { c in
            SubscriptionReducerState(subscription: c.generate(),
                                     receiptData: c.generate())
        }
    }
}

extension SubscriptionAuthStateReducerEnvironment: Arbitrary {
    public static var arbitrary: Gen<SubscriptionAuthStateReducerEnvironment> {
        Gen.compose { c in

            let sharedDBContainer = TestSharedDBContainer(state:
                MutableDBContainer(subscriptionAuths: nil,
                                   containerRejectedSubscriptionAuthIdReadAtLeastUpToSequenceNumber: 0))

            return SubscriptionAuthStateReducerEnvironment(
                feedbackLogger: FeedbackLogger(StdoutFeedbackLogger()),
                httpClient: c.generate(),
                notifier: DevNullNotifier(),
                notifierUpdatedSubscriptionAuthsMessage: c.generate(),
                sharedDB: sharedDBContainer,
                tunnelStatusSignal: SignalProducer<TunnelProviderVPNStatus, Never>(value: c.generate()),
                tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>(value: c.generate()),
                clientMetaData: ClientMetaData(MockAppInfoProvider()),
                getCurrentTime: {
                    return Date()
                },
                compareDates: { date1, date2, _ -> ComparisonResult in
                    return PsiApiTestingCommon.compareDates(date1, to: date2)
                }
            )
        }
    }
}

extension SubscriptionAuthState: Arbitrary {
    public static var arbitrary: Gen<SubscriptionAuthState> {
        Gen.compose { c in
            var subAuthState = SubscriptionAuthState()

            let authStates: [SubscriptionPurchaseAuthState] = c.generate()
            if authStates.count > 0 {
                subAuthState.purchasesAuthState = [:]
                for purchaseAuthState in authStates {
                    subAuthState.purchasesAuthState![purchaseAuthState.purchase.originalTransactionID] = purchaseAuthState
                }
            }

            // Note: in the future it could be worth selecting a
            // random number of the purchases above to add.
            subAuthState.transactionsPendingAuthRequest = c.generate()

            return subAuthState
        }
    }
}

extension SubscriptionPurchaseAuthState: Arbitrary {
    public static var arbitrary: Gen<SubscriptionPurchaseAuthState> {
        Gen.compose { c in
            SubscriptionPurchaseAuthState(purchase: c.generate(), signedAuthorization: c.generate())
        }
    }
}

extension SubscriptionPurchaseAuthState.AuthorizationState: Arbitrary {
    public static var arbitrary: Gen<SubscriptionPurchaseAuthState.AuthorizationState> {
        Gen.one(of: [
            // All cases should be covered.
            Gen.pure(SubscriptionPurchaseAuthState.AuthorizationState.notRequested),
            ErrorEvent<ErrorRepr>.arbitrary.map(
                SubscriptionPurchaseAuthState.AuthorizationState.requestError
            ),
            RequestRejectedReason.arbitrary.map(
                SubscriptionPurchaseAuthState.AuthorizationState.requestRejected
            ),
            SignedData<SignedAuthorization>.arbitrary.map(
                SubscriptionPurchaseAuthState.AuthorizationState.authorization
            ),
            SignedData<SignedAuthorization>.arbitrary.map(
                SubscriptionPurchaseAuthState.AuthorizationState.rejectedByPsiphon
            ),
        ])
    }
}

extension SubscriptionPurchaseAuthState.AuthorizationState.RequestRejectedReason: Arbitrary {
    public static var arbitrary: Gen<SubscriptionPurchaseAuthState.AuthorizationState.RequestRejectedReason> {
        Gen<SubscriptionPurchaseAuthState.AuthorizationState.RequestRejectedReason>.fromElements(of:
            SubscriptionPurchaseAuthState.AuthorizationState.RequestRejectedReason.allCases)
    }
}

extension SubscriptionAuthStateAction: Arbitrary {
    public static var arbitrary: Gen<SubscriptionAuthStateAction> {
        Gen.one(of: [
            // Note: does not cover all cases, omits internal actions
            // which are only generated by the reducer itself.
            StoredDataUpdateType.arbitrary.map(
                SubscriptionAuthStateAction.localDataUpdate
            ),
            Gen.zip(Result<SubscriptionAuthState.PurchaseAuthStateDict, SystemErrorEvent>.arbitrary,
                    StoredDataUpdateType?.arbitrary).map(
                        SubscriptionAuthStateAction.didLoadStoredPurchaseAuthState
            ),
            Gen.pure(SubscriptionAuthStateAction.requestAuthorizationForPurchases),
            // Omitted internal actions:
            //SubscriptionAuthStateAction._localDataUpdateResult(...),
            //SubscriptionAuthStateAction._authorizationRequestResult(...)
        ])
    }
}

extension SubscriptionAuthStateAction.StoredDataUpdateType: Arbitrary {
    public static var arbitrary: Gen<SubscriptionAuthStateAction.StoredDataUpdateType> {
        Gen.one(of: [
            // All cases should be covered.
            Gen.pure(SubscriptionAuthStateAction.StoredDataUpdateType.didUpdateRejectedSubscriptionAuthIDs),
            ReceiptReadReason.arbitrary.map(
                SubscriptionAuthStateAction.StoredDataUpdateType.didRefreshReceiptData
            )
        ])
    }
}
