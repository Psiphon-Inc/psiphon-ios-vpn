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

extension ReceiptData {
    
    static func mock(
        subscriptionInAppPurchases: Set<SubscriptionIAPPurchase> = Set([]),
        consumableInAppPurchases: Set<ConsumableIAPPurchase> = Set([]),
        readDate: Date = Date()
    ) -> ReceiptData {
        ReceiptData(
            filename: "receipt", // unused in tests.
            subscriptionInAppPurchases: subscriptionInAppPurchases,
            consumableInAppPurchases: consumableInAppPurchases,
            data: Data(), // unused in tests.
            readDate: readDate
        )
    }
    
}

final class MockPsiCashEffects: PsiCashEffectsProtocol {
    
    private let initGen: Gen<Result<PsiCashLibInitSuccess, ErrorRepr>>?
    private let libDataGen: Gen<PsiCashLibData>?
    private let refreshStateGen: Gen<PsiCashRefreshResult>?
    private let purchaseProductGen: Gen<NewExpiringPurchaseResult>?
    private let modifyLandingPageGen: Gen<URL>?
    private let rewardedVideoCustomDataGen: Gen<String>?
    
    init(
        initGen: Gen<Result<PsiCashLibInitSuccess, ErrorRepr>>? = nil,
        libDataGen: Gen<PsiCashLibData>? = nil,
        refreshStateGen: Gen<PsiCashRefreshResult>? = nil,
        purchaseProductGen: Gen<NewExpiringPurchaseResult>? = nil,
        modifyLandingPageGen: Gen<URL>? = nil,
        rewardedVideoCustomDataGen: Gen<String>? = nil
    ) {
        self.initGen = initGen
        self.libDataGen = libDataGen
        self.refreshStateGen = refreshStateGen
        self.purchaseProductGen = purchaseProductGen
        self.modifyLandingPageGen = modifyLandingPageGen
        self.rewardedVideoCustomDataGen = rewardedVideoCustomDataGen
    }
    
    func initialize(
        fileStoreRoot: String?,
        psiCashLegacyDataStore: UserDefaults,
        tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    ) -> Effect<Result<PsiCashLibInitSuccess, ErrorRepr>> {
        Effect(value: returnGeneratedOrFail(initGen))
    }
    
    func libData() -> PsiCashLibData {
        returnGeneratedOrFail(libDataGen)
    }
    
    func refreshState(
        priceClasses: [PsiCashTransactionClass],
        tunnelConnection: TunnelConnection,
        clientMetaData: ClientMetaData
    ) -> Effect<PsiCashRefreshResult> {
        
        Effect(value: returnGeneratedOrFail(refreshStateGen))
        
    }
    
    func purchaseProduct(
        purchasable: PsiCashPurchasableType,
        tunnelConnection: TunnelConnection,
        clientMetaData: ClientMetaData
    ) -> Effect<NewExpiringPurchaseResult> {
        
        Effect(value: returnGeneratedOrFail(purchaseProductGen))
        
    }
    
    func modifyLandingPage(_ url: URL) -> Effect<URL> {

        Effect(value: returnGeneratedOrFail(modifyLandingPageGen))
        
    }
    
    func rewardedVideoCustomData() -> String? {
        
        returnGeneratedOrFail(rewardedVideoCustomDataGen)
        
    }
    
    func removePurchasesNotIn(psiCashAuthorizations: Set<String>) -> Effect<Never> {
        return .empty
    }
    
    func accountLogout() -> Effect<PsiCashAccountLogoutResult> {
        fatalError("not implemented")
        return .empty
    }
    
    func accountLogin(
        tunnelConnection: TunnelConnection,
        username: String,
        password: SecretString
    ) -> Effect<PsiCashAccountLoginResult> {
        fatalError("not implemented")
        return .empty
    }
    
    func setLocale(_ locale: Locale) -> Effect<Never> {
        return .empty
    }
    
}

extension PaymentQueue {
    
    static func mock(
        transactions: Gen<[PaymentTransaction]>? = nil,
        addPayment: ((AppStoreProduct) -> Effect<Never>)? = nil,
        finishTransaction: ((PaymentTransaction) -> Effect<Never>)? = nil
    ) -> PaymentQueue {
        return PaymentQueue(
            transactions: { () -> Effect<[PaymentTransaction]> in
                Effect(value: returnGeneratedOrFail(transactions))
            },
            addPayment: { product -> Effect<Never> in
                guard let addPayment = addPayment else { XCTFatal() }
                return addPayment(product)
            },
            addObserver: { _ -> Effect<Never> in
                return .empty
            },
            removeObserver: { _ -> Effect<Never> in
                return .empty
            },
            finishTransaction: { paymentTx -> Effect<Never> in
                guard let f = finishTransaction else {
                    XCTFatal()
                }
                return f(paymentTx)
            })
    }
    
}

extension IAPEnvironment {
    
    static func mock(
        _ feedbackLogger: FeedbackLogger,
        tunnelStatusSignal: @autoclosure () -> SignalProducer<TunnelProviderVPNStatus, Never>? = nil,
        tunnelConnectionRefSignal: @autoclosure () -> SignalProducer<TunnelConnection?, Never>? = nil,
        psiCashEffects: PsiCashEffectsProtocol? = nil,
        paymentQueue: PaymentQueue? = nil,
        clientMetaData: (() -> ClientMetaData)? = nil,
        isSupportedProduct: ((ProductID) -> AppStoreProductType?)? = nil,
        psiCashStore: ((PsiCashAction) -> Effect<Never>)? = nil,
        appReceiptStore: ((ReceiptStateAction) -> Effect<Never>)? = nil,
        httpClient: HTTPClient? = nil,
        getCurrentTime: (() -> Date)? = nil
    ) -> IAPEnvironment {

        let _tunnelStatusSignal = tunnelStatusSignal() ?? SignalProducer(value: .connected)
        
        let _tunnelConnectionRefSignal = tunnelConnectionRefSignal() ??
            SignalProducer(value: .some(TunnelConnection { .connection(.connected) }))
            
        return IAPEnvironment(
            feedbackLogger: feedbackLogger,
            tunnelStatusSignal: _tunnelStatusSignal,
            tunnelConnectionRefSignal: _tunnelConnectionRefSignal,
            psiCashEffects: psiCashEffects ?? MockPsiCashEffects(),
            clientMetaData: clientMetaData ?? { ClientMetaData(MockAppInfoProvider()) },
            paymentQueue: paymentQueue ?? PaymentQueue.mock(),
            psiCashPersistedValues: MockPsiCashPersistedValues(),
            isSupportedProduct: isSupportedProduct ?? { _ in XCTFatal() },
            psiCashStore: psiCashStore ?? { _ in XCTFatal() },
            appReceiptStore: appReceiptStore ?? { _ in XCTFatal() },
            httpClient: httpClient ?? EchoHTTPClient().client,
            getCurrentTime: getCurrentTime ?? { XCTFatal() }
        )
    }
    
}
