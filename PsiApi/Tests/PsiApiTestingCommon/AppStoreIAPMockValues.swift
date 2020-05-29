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
import PsiCashClient
import Testing
import StoreKit
import SwiftCheck
import Utilities
@testable import PsiApi
@testable import AppStoreIAP

extension PsiCashEffects {
    
    static func mock(
        libData: Gen<PsiCashLibData>? = nil,
        refreshState: Gen<PsiCashRefreshResult>? = nil,
        purchaseProduct: Gen<PsiCashPurchaseResult>? = nil,
        modifyLandingPage: Gen<URL>? = nil,
        rewardedVideoCustomData: Gen<String>? = nil
    ) -> PsiCashEffects {
        PsiCashEffects(
            libData: { () -> PsiCashLibData in
                returnGeneratedOrFail(libData)
            },
            refreshState: { _, _ -> Effect<PsiCashRefreshResult> in
                Effect(value: returnGeneratedOrFail(refreshState))
            },
            purchaseProduct: { _, _ -> Effect<PsiCashPurchaseResult> in
                Effect(value: returnGeneratedOrFail(purchaseProduct))
            },
            modifyLandingPage: { _ -> Effect<URL> in
                Effect(value: returnGeneratedOrFail(modifyLandingPage))
            },
            rewardedVideoCustomData: { () -> String? in
                returnGeneratedOrFail(rewardedVideoCustomData)
            },
            expirePurchases: { _ -> Effect<Never> in
                return .empty
            })
    }
    
}

extension PaymentQueue {
    
    static func mock(
        transactions: Gen<[PaymentTransaction]>? = nil,
        addPayment: ((IAPPurchasableProduct) -> AddedPayment)? = nil
    ) -> PaymentQueue {
        return PaymentQueue(
            transactions: { () -> Effect<[PaymentTransaction]> in
                Effect(value: returnGeneratedOrFail(transactions))
            },
            addPayment: { product -> Effect<AddedPayment> in
                guard let addPayment = addPayment else { XCTFatal() }
                return Effect(value: addPayment(product))
            },
            addObserver: { _ -> Effect<Never> in
                return .empty
            },
            removeObserver: { _ -> Effect<Never> in
                return .empty
            },
            finishTransaction: { _ -> Effect<Never> in
                return .empty
            })
    }
    
}

func mockIAPEnvironment(
    _ feedbackLogger: FeedbackLogger,
    tunnelStatusSignal: @autoclosure () -> SignalProducer<TunnelProviderVPNStatus, Never>? = nil,
    tunnelConnectionRefSignal: @autoclosure () -> SignalProducer<TunnelConnection?, Never>? = nil,
    psiCashEffects: PsiCashEffects? = nil,
    paymentQueue: PaymentQueue? = nil,
    psiCashStore: ((PsiCashAction) -> Effect<Never>)? = nil,
    appReceiptStore: ((ReceiptStateAction) -> Effect<Never>)? = nil,
    httpClient: HTTPClient? = nil
) -> IAPEnvironment {

    let _tunnelStatusSignal = tunnelStatusSignal() ?? SignalProducer(value: .connected)
    
    let _tunnelConnectionRefSignal = tunnelConnectionRefSignal() ??
        SignalProducer(value: .some(TunnelConnection { .connection(.connected) }))
        
    let _psiCashStore = psiCashStore ?? { _ in XCTFatal() }
    
    let _appReceiptStore = appReceiptStore ?? { _ in XCTFatal() }
    
    let _httpClient = httpClient ?? EchoHTTPClient().client
        
    return IAPEnvironment(
        feedbackLogger: feedbackLogger,
        tunnelStatusSignal: _tunnelStatusSignal,
        tunnelConnectionRefSignal: _tunnelConnectionRefSignal,
        psiCashEffects: psiCashEffects ?? PsiCashEffects.mock(),
        clientMetaData: ClientMetaData(MockAppInfoProvider()),
        paymentQueue: paymentQueue ?? PaymentQueue.mock(),
        psiCashStore: _psiCashStore,
        appReceiptStore: _appReceiptStore,
        httpClient: _httpClient,
        getCurrentTime: { Date() }
    )
}
