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
import PsiApi
import PsiCashClient
import Testing
import StoreKit
@testable import AppStoreIAP

func mockLibData(
    fullAuthPackage: Bool = true,
    balance: @autoclosure () -> PsiCashAmount? = nil,
    availableProducts: @autoclosure () -> PsiCashParsed<PsiCashPurchasableType>? = nil,
    activePurchases: @autoclosure () -> PsiCashParsed<PsiCashPurchasedType>? = nil
) -> PsiCashLibData {
    PsiCashLibData(
        authPackage: PsiCashAuthPackage(
            withTokenTypes: fullAuthPackage ? ["earner", "indicator", "spender"] : []
        ),
        balance: balance() ?? .zero,
        availableProducts: availableProducts() ?? PsiCashParsed(items: [], parseErrors: []),
        activePurchases: activePurchases() ?? PsiCashParsed(items: [], parseErrors: [])
    )
}

extension PsiCashEffects {
    
    static func mock(
        libData: @autoclosure () -> Generator<PsiCashLibData>? = nil,
        refreshState: @autoclosure () -> Generator<PsiCashRefreshResult>? = nil,
        purchaseProduct: @autoclosure () -> Generator<PsiCashPurchaseResult>? = nil,
        modifyLandingPage: @autoclosure () -> Generator<URL>? = nil,
        rewardedVideoCustomData: @escaping @autoclosure () -> String? = nil
    ) -> PsiCashEffects {
        
        var libDataGen = libData() ?? Generator(sequence: [mockLibData()])
        
        var refreshStateGen = refreshState() ??
            Generator(sequence: [.completed(.success(mockLibData()))])
        
        var purchaseProductGen = purchaseProduct() ?? .empty()
        
        var modifyLandingPageGen = modifyLandingPage() ?? .empty()
        
        return PsiCashEffects(
            libData: { () -> PsiCashLibData in
                guard let next = libDataGen.next() else { XCTFatal() }
                return next
        },
            refreshState: { _, _ -> Effect<PsiCashRefreshResult> in
                guard let next = refreshStateGen.next() else { XCTFatal() }
                return Effect(value: next)
        },
            purchaseProduct: { _, _ -> Effect<PsiCashPurchaseResult> in
                guard let next = purchaseProductGen.next() else { XCTFatal() }
                return Effect(value: next)
        },
            modifyLandingPage: { _ -> Effect<URL> in
                guard let next = modifyLandingPageGen.next() else { XCTFatal() }
                return Effect(value: next)
        },
            rewardedVideoCustomData: { () -> String? in
                return rewardedVideoCustomData()
        },
            expirePurchases: { _ -> Effect<Never> in
                return .empty
        })
    }
    
}

extension PaymentQueue {
    
    static func mock(
        transactions: @autoclosure () -> [SKPaymentTransaction]? = nil
    ) -> PaymentQueue {
        let _transactions = transactions() ?? [SKPaymentTransaction]()
        
        return PaymentQueue(
            transactions: { () -> Effect<[SKPaymentTransaction]> in
                Effect(value: _transactions)
        },
            addPayment: { product -> Effect<AddedPayment> in
                Effect(value: AddedPayment(product: product, paymentObj: SKPayment()))
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
    psiCashEffects: @autoclosure () -> PsiCashEffects? = nil,
    transactions: @autoclosure () -> [SKPaymentTransaction]? = nil,
    psiCashStore: ((PsiCashAction) -> Effect<Never>)? = nil,
    appReceiptStore: ((ReceiptStateAction) -> Effect<Never>)? = nil,
    httpClient: HTTPClient? = nil
) -> IAPEnvironment {

    let _tunnelStatusSignal = tunnelStatusSignal() ?? SignalProducer(value: .connected)
    
    let _tunnelConnectionRefSignal = tunnelConnectionRefSignal() ??
        SignalProducer(value: .some(TunnelConnection { .connection(.connected) }))
    
    let _psiCashEffects = psiCashEffects() ?? .mock()
    
    let _psiCashStore = psiCashStore ?? { _ in .empty }
    
    let _appReceiptStore = appReceiptStore ?? { _ in .empty }
    
    let _httpClient = httpClient ?? EchoHTTPClient().client
        
    return IAPEnvironment(
        feedbackLogger: feedbackLogger,
        tunnelStatusSignal: _tunnelStatusSignal,
        tunnelConnectionRefSignal: _tunnelConnectionRefSignal,
        psiCashEffects: _psiCashEffects,
        clientMetaData: ClientMetaData(MockAppInfoProvider()),
        paymentQueue: .mock(transactions: transactions()),
        psiCashStore: _psiCashStore,
        appReceiptStore: _appReceiptStore,
        httpClient: _httpClient,
        getCurrentTime: { Date() }
    )
}

extension PaymentTransaction {
    
    static func mock(
        transactionID: (() -> TransactionID)? = nil,
        transactionDate: (() -> Date)? = nil,
        productID: (() -> String)? = nil,
        transactionState: (() -> TransactionState)? = nil,
        isEqual: ((PaymentTransaction) -> Bool)? = nil
    ) -> PaymentTransaction {
        PaymentTransaction(
            transactionID: transactionID ?? { TransactionID(stringLiteral: "TransactionID") },
            transactionDate: transactionDate ?? { Date() },
            productID: productID ?? { "ProductID" },
            transactionState: transactionState ?? { TransactionState.completed(.success(.purchased)) },
            isEqual: isEqual ?? { _ in true },
            skPaymentTransaction: { nil })
    }
    
}
