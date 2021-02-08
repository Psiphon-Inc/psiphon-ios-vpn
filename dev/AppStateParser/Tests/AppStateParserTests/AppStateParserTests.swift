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

import XCTest
import SwiftParsec
@testable import AppStateParser

final class AppStateParserTests: XCTestCase {

    // TODO: For development testing, should be replaced with an actual test.
    // Understanding how String(describing:) prints Swift values.
    func swiftValueTest() {

        struct S {
            let a: Set<String>
        }

        enum T {
            case set(Set<String>)
            case dict([Int: Int])
            case strct(S)
            case set2(aa: Set<String>)
            case dict2(Int, dict:[String: String])
            case string(String)
            case date(Date)
            case tuple((Int, Int))
            case tuple2((a: Int, b: Int, Int))
        }

        print(T.tuple((1, 2)))
        print(T.tuple2((a: 1, b: 2, 3)))
        print(T.string("mystring"))
        print(T.date(Date()))
        print(T.dict2(4, dict:["oh": "no"]))
        print(S(a: ["hi"]))
        print(T.strct(S(a: ["set2"])))
        print(T.dict([1: 2, 3: 4]))
        print(T.set(Set<String>(["ohoh"])))

    }

    // TODO: For development testing, should be replaced with an actual test.
    func testManual() {
        let input = "ProviderManagerLoadState<PsiphonTPM>(value: ProviderManagerLoadState<PsiphonTPM>.LoadState.loaded, value2: \"hi\")"

        print("⌨️", input)

        let result = AppStateValue.parser.runSafe(userState: (), sourceName: "", input: input)

        print(result)

    }

    // TODO: For development testing, should be replaced with an actual test.
    func testTypeParser() {
        var inputs = [
            "Pending<()>",

            "Pending<Result>",

            "Pending.A<Result>",

            "Pending<Dictionary.A<String.A, Int.A>, Bool.A>.completed",

            "Pending<Dictionary<String.A, Int.A>, Bool.A>.completed",

            "Pending<Result<Unit, ErrorEvent<PsiCashClient.TunneledPsiCashRequestError<PsiCashClient.PsiCashRequestError<PsiCashClient.PsiCashRefreshErrorStatus>>>>>.completed"
        ]

        //    inputs = [inputs[2]]

        for (i, input) in inputs.enumerated() {
            let result = typeParser.runSafe(userState: (), sourceName: "", input: input)
            print("\(i), \(input) → \(result)\n")
        }
    }

    // TODO: For development testing, should be replaced with an actual test.
    func testAppStateParser() {
        var inputs = [
            "tuple(1, 2)",
            "tuple2(a: 1, b: 2, 3)",
            "string(\"mystring\")",
            "date(2020-11-27 22:43:50 +0000)",
            "T.set2(aa: Set([\"aa\"]), bb: Set([\"b1\", \"b2\", \"b2\"]))",
            "S(a: Set([\"hi\"]))",
            "strct(AppStateParser.S(a: Set([\"set2\"])))",
            "dict([1: 2, 3: 4])",
            "set(Set([\"ohoh\"]))",
            "T.dict2(4, [\"oh\": \"no\"])",
            "dict2(4, dict: [\"oh\": \"no\"])",
            "A<B>(a:a)",
            "A<B>(a:())",
            "A<B>(a:(()))",
            "Q<()>(a: AppStateParser.Unit<()>.unit())",
            "Q<()>(a: [\"answer\":Q<()>(a: AppStateParser.Unit<()>.unit()), \"answer2\": \"whats the question\"])",
            "A<B>(a:Set([]))",
            "A<B>(a:[])",
            "A<B>(a:[:])",
            "A([\"answer\":42])",
            "A<B>(a:[\"hi\":42])",
            "A<B>(a: \"hello\")",
            "A<B>(a: nil)",
            "A<B>(set: C(a: \"asdf\"))",
            "A<B>(set: C([]))",
            "MainViewState(alertMessages: Set([]), psiCashViewState: nil)",
            "A(b: Set([]), c: Optional([:]))",
            "A(b: P.completed)",
            "A(b: P.completed())",
            "A(b: P.completed([]))",
            "A(b: P.completed(R.success([])))",
            "A(b: P<Array<PPAP>,R<A<P>,E<S>>>.completed(R<A<PPAP>,E<S>>.success([])), psiCashRequest: nil)",

            "UserFeedback([\"uploadDiagnostics\": true, \"submitTime\": 2020-11-24 17:35:13 +0000])",

            "VPNProviderManagerState<PsiphonTPM>(tunnelIntent: Optional(TunnelStartStopIntent.stop))",

            "VPNProviderManagerState<PsiphonTPM>(tunnelIntent: Optional(TunnelStartStopIntent.stop), providerVPNStatus: disconnected)",

            "Optional(PendingValue<TunnelProviderStartStopAction, Result<TunnelProviderStartStopAction, ErrorEvent<StartTunnelError>>>.completed(Result<TunnelProviderStartStopAction, ErrorEvent<StartTunnelError>>.success(TunnelProviderStartStopAction.stopVPN)))",

            "A(providerSyncResult: Pending<Optional<ErrorEvent<TunnelProviderSyncedState.SyncError>>>.completed(nil))",

            "A(a: O(P<T>.completed(R<A>.success)))",

            "A(a: R.success)",

            "A(a: R.success())",

            "A(a: R.success([]))",

            "A(a: R<A>.success(R<B>.completed))",

            "A(a: O(P<T>.completed(R<A>.success())))",

            "A()",

            "A([])",

            "A(Result.connected)",

            "P<T>.completed(R<A>.success(Tunnel.stopVPN))",

            "P<T>.completed(R<A>.success(Tunnel.stopVPN))",

            "A(a: O(P<T>.completed(R<A>.success(Tunnel.stopVPN))))",

            "A(startStopState: Optional(PendingValue<TunnelProviderStartStopAction, Result<TunnelProviderStartStopAction, ErrorEvent<StartTunnelError>>>.completed(Result<TunnelProviderStartStopAction, ErrorEvent<StartTunnelError>>.success(TunnelProviderStartStopAction.stopVPN))))",


            "VPNProviderManagerState<PsiphonTPM>(tunnelIntent: Optional(TunnelStartStopIntent.stop), providerVPNStatus: disconnected)",

            "Pending<Optional<ErrorEvent<TunnelProviderSyncedState.SyncError>>>.completed(nil)",

            "VPNProviderManagerState<PsiphonTPM>(tunnelIntent: Optional(TunnelStartStopIntent.stop), providerVPNStatus: disconnected, providerStatus: Pending<A<B>>.completed)",

            "VPNProviderManagerState<PsiphonTPM>(tunnelIntent: Optional(TunnelStartStopIntent.stop), providerStatus: Pending<Optional<ErrorEvent<TunnelProviderSyncedState.SyncError>>>.completed(nil), providerVPNStatus: disconnected)",

            "A(pendingPsiCashRefresh: Pending<Result<Unit, Error>>(completed))",

            "A(pendingPsiCashRefresh: Pending<Result<Unit, Error>>.completed)",

            "A(pendingPsiCashRefresh: Pending<Result<Unit, ErrorEvent<PsiCashClient.TunneledPsiCashRequestError<PsiCashClient.PsiCashRequestError<PsiCashClient.PsiCashRefreshErrorStatus>>>>>.completed)",

            "A(a: \"hi\")",

            "A(a: L.loaded(\"hi\"))",

            "ProviderManagerLoadState<PsiphonTPM>(value: ProviderManagerLoadState<PsiphonTPM>.LoadState.loaded, value2: \"hi\")",

            "A(a: LoadState.loaded(\"{ localizedDescription = Psiphon enabled = YES protocolConfiguration = { serverAddress = <9-char-str> disconnectOnSleep = NO includeAllNetworks = NO excludeLocalNetworks = YES enforceRoutes = NO providerBundleIdentifier = ca.psiphon.PsiphonVPN } onDemandEnabled = NO onDemandRules = ( { action = connect interfaceTypeMatch = any }, ) }\"))",

            "ErrorEvent<TPMError>(error: Psiphon.ProviderManagerLoadState<PsiApi.PsiphonTPM>.TPMError.failedConfigLoadSave(__C_Synthesized.related decl 'e' for NEVPNError(_nsError: \"Error Domain=NEVPNErrorDomain Code=5 permission denied UserInfo={NSLocalizedDescription=permission denied}\")), date: 2020-11-27 22:43:50 +0000)",

            "AppState(vpnState: SerialEffectState<VPNProviderManagerState<PsiphonTPM>, VPNProviderManagerStateAction<PsiphonTPM>>(pendingActionQueue: Queue<VPNProviderManagerStateAction<PsiphonTPM>>(items: []), pendingEffectActionQueue: Queue<VPNProviderManagerStateAction<PsiphonTPM>>(items: []), pendingEffectCompletion: false, value: VPNProviderManagerState<PsiphonTPM>(tunnelIntent: Optional(TunnelStartStopIntent.stop), loadState: ProviderManagerLoadState<PsiphonTPM>(value: ProviderManagerLoadState<PsiphonTPM>.LoadState.loaded(PsiphonTPM(\\\"{ localizedDescription = Psiphon enabled = YES protocolConfiguration = { serverAddress = <9-char-str> disconnectOnSleep = NO includeAllNetworks = NO excludeLocalNetworks = YES enforceRoutes = NO providerBundleIdentifier = ca.psiphon.PsiphonVPN } onDemandEnabled = NO onDemandRules = ( { action = connect interfaceTypeMatch = any }, ) }\\\"))), providerVPNStatus: disconnected, startStopState: nil, providerSyncResult: Pending<Optional<ErrorEvent<TunnelProviderSyncedState.SyncError>>>.completed(nil))), psiCashBalance: PsiCashClient.PsiCashBalance(pendingExpectedBalanceIncrease: nil, optimisticBalance: PsiCash(inPsi: 90.00), lastRefreshBalance: PsiCash(inPsi: 90.00)), psiCash: PsiCashClient.PsiCashState(purchasing: PsiCashClient.PsiCashPurchasingState.none, rewardedVideo: PsiCashClient.RewardedVideoState(loading: Result<PsiCashClient.RewardedVideoLoadStatus, ErrorEvent<PsiCashClient.RewardedVideoAdLoadError>>.success(PsiCashClient.RewardedVideoLoadStatus.none), presentation: PsiCashClient.RewardedVideoPresentation.didDisappear, dismissed: false, rewarded: false), libData: PsiCashClient.PsiCashLibData(authPackage: PsiCashClient.PsiCashAuthPackage(hasEarnerToken: true, hasIndicatorToken: true, hasSpenderToken: true), balance: PsiCash(inPsi: 90.00), availableProducts: PsiCashClient.PsiCashParsed<PsiCashClient.PsiCashPurchasableType>(items: [PsiCashClient.PsiCashPurchasableType.speedBoost(PsiCashClient.PsiCashPurchasable<PsiCashClient.SpeedBoostProduct>(product: PsiCashClient.SpeedBoostProduct(transactionClass: PsiCashClient.PsiCashTransactionClass.speedBoost, distinguisher: \\\"1hr\\\", hours: 1), price: PsiCash(inPsi: 100.00))), PsiCashClient.PsiCashPurchasableType.speedBoost(PsiCashClient.PsiCashPurchasable<PsiCashClient.SpeedBoostProduct>(product: PsiCashClient.SpeedBoostProduct(transactionClass: PsiCashClient.PsiCashTransactionClass.speedBoost, distinguisher: \\\"2hr\\\", hours: 2), price: PsiCash(inPsi: 200.00))), PsiCashClient.PsiCashPurchasableType.speedBoost(PsiCashClient.PsiCashPurchasable<PsiCashClient.SpeedBoostProduct>(product: PsiCashClient.SpeedBoostProduct(transactionClass: PsiCashClient.PsiCashTransactionClass.speedBoost, distinguisher: \\\"3hr\\\", hours: 3), price: PsiCash(inPsi: 300.00))), PsiCashClient.PsiCashPurchasableType.speedBoost(PsiCashClient.PsiCashPurchasable<PsiCashClient.SpeedBoostProduct>(product: PsiCashClient.SpeedBoostProduct(transactionClass: PsiCashClient.PsiCashTransactionClass.speedBoost, distinguisher: \\\"4hr\\\", hours: 4), price: PsiCash(inPsi: 400.00))), PsiCashClient.PsiCashPurchasableType.speedBoost(PsiCashClient.PsiCashPurchasable<PsiCashClient.SpeedBoostProduct>(product: PsiCashClient.SpeedBoostProduct(transactionClass: PsiCashClient.PsiCashTransactionClass.speedBoost, distinguisher: \\\"5hr\\\", hours: 5), price: PsiCash(inPsi: 500.00))), PsiCashClient.PsiCashPurchasableType.speedBoost(PsiCashClient.PsiCashPurchasable<PsiCashClient.SpeedBoostProduct>(product: PsiCashClient.SpeedBoostProduct(transactionClass: PsiCashClient.PsiCashTransactionClass.speedBoost, distinguisher: \\\"6hr\\\", hours: 6), price: PsiCash(inPsi: 600.00))), PsiCashClient.PsiCashPurchasableType.speedBoost(PsiCashClient.PsiCashPurchasable<PsiCashClient.SpeedBoostProduct>(product: PsiCashClient.SpeedBoostProduct(transactionClass: PsiCashClient.PsiCashTransactionClass.speedBoost, distinguisher: \\\"7hr\\\", hours: 7), price: PsiCash(inPsi: 700.00))), PsiCashClient.PsiCashPurchasableType.speedBoost(PsiCashClient.PsiCashPurchasable<PsiCashClient.SpeedBoostProduct>(product: PsiCashClient.SpeedBoostProduct(transactionClass: PsiCashClient.PsiCashTransactionClass.speedBoost, distinguisher: \\\"8hr\\\", hours: 8), price: PsiCash(inPsi: 800.00))), PsiCashClient.PsiCashPurchasableType.speedBoost(PsiCashClient.PsiCashPurchasable<PsiCashClient.SpeedBoostProduct>(product: PsiCashClient.SpeedBoostProduct(transactionClass: PsiCashClient.PsiCashTransactionClass.speedBoost, distinguisher: \\\"9hr\\\", hours: 9), price: PsiCash(inPsi: 900.00)))], parseErrors: [PsiCashClient.PsiCashParseError.speedBoostParseFailure(message: \\\"24hr\\\"), PsiCashClient.PsiCashParseError.speedBoostParseFailure(message: \\\"7day\\\"), PsiCashClient.PsiCashParseError.speedBoostParseFailure(message: \\\"31day\\\")]), activePurchases: PsiCashClient.PsiCashParsed<PsiCashClient.PsiCashPurchasedType>(items: [], parseErrors: [])), pendingPsiCashRefresh: Pending<Result<Unit, ErrorEvent<PsiCashClient.PsiCashRefreshError>>>.completed(Result<Unit, ErrorEvent<PsiCashClient.PsiCashRefreshError>>.success(Unit.unit)), libLoaded: true), appReceipt: ReceiptState(receiptData: nil, remoteReceiptRefreshState: PendingValue<__C.SKReceiptRefreshRequest, Result<Unit, ErrorEvent<SystemError>>>.completed(Result<Unit, ErrorEvent<SystemError>>.success(Unit.unit)), remoteRefreshAppReceiptPromises: []), subscription: SubscriptionState(status: SubscriptionStatus.notSubscribed), subscriptionAuthState: SubscriptionAuthState(transactionsPendingAuthRequest: Set([]), purchasesAuthState: Optional([:])), iapState: IAPState(unfinishedPsiCashTx: nil, purchasing: [:], objcSubscriptionPromises: []), products: PsiCashAppStoreProductsState(psiCashProducts: PendingValue<Array<ParsedPsiCashAppStorePurchasable>, Result<Array<ParsedPsiCashAppStorePurchasable>, ErrorEvent<SystemError>>>.completed(Result<Array<ParsedPsiCashAppStorePurchasable>, ErrorEvent<SystemError>>.success([ParsedPsiCashAppStorePurchasable.purchasable(PsiCashPurchasableViewModel(product: PsiCashPurchasableViewModel.ProductType.product(AppStoreProduct(type: psiCash, productID: \\\"ca.psiphon.Consumable.PsiCash.1000\\\", localizedDescription: \\\"10 hours of Speed Boost\\\", price: localizedPrice(price: 1.3900000000000001, priceLocale: PriceLocale(locale: \\\"(en_CA@currency=CAD (fixed)\\\")))), title: \\\"1,000\\\", subtitle: \\\"10 hours of Speed Boost\\\", localizedPrice: LocalizedPrice.localizedPrice(price: 1.3900000000000001, priceLocale: PriceLocale(locale: \\\"(en_CA@currency=CAD (fixed)\\\")), clearedForSale: true)), ParsedPsiCashAppStorePurchasable.purchasable(PsiCashPurchasableViewModel(product: PsiCashPurchasableViewModel.ProductType.product(AppStoreProduct(type: psiCash, productID: \\\"ca.psiphon.Consumable.PsiCash.4000\\\", localizedDescription: \\\"40 hours of Speed Boost\\\", price: localizedPrice(price: 3.9899999999999998, priceLocale: PriceLocale(locale: \\\"(en_CA@currency=CAD (fixed)\\\")))), title: \\\"4,000\\\", subtitle: \\\"40 hours of Speed Boost\\\", localizedPrice: LocalizedPrice.localizedPrice(price: 3.9899999999999998, priceLocale: PriceLocale(locale: \\\"(en_CA@currency=CAD (fixed)\\\")), clearedForSale: true)), ParsedPsiCashAppStorePurchasable.purchasable(PsiCashPurchasableViewModel(product: PsiCashPurchasableViewModel.ProductType.product(AppStoreProduct(type: psiCash, productID: \\\"ca.psiphon.Consumable.PsiCash.10000\\\", localizedDescription: \\\"100 hours of Speed Boost\\\", price: localizedPrice(price: 9.99, priceLocale: PriceLocale(locale: \\\"(en_CA@currency=CAD (fixed)\\\")))), title: \\\"10,000\\\", subtitle: \\\"100 hours of Speed Boost\\\", localizedPrice: LocalizedPrice.localizedPrice(price: 9.99, priceLocale: PriceLocale(locale: \\\"(en_CA@currency=CAD (fixed)\\\")), clearedForSale: true)), ParsedPsiCashAppStorePurchasable.purchasable(PsiCashPurchasableViewModel(product: PsiCashPurchasableViewModel.ProductType.product(AppStoreProduct(type: psiCash, productID: \\\"ca.psiphon.Consumable.PsiCash.30000\\\", localizedDescription: \\\"300 hours of Speed Boost\\\", price: localizedPrice(price: 29.99, priceLocale: PriceLocale(locale: \\\"(en_CA@currency=CAD (fixed)\\\")))), title: \\\"30,000\\\", subtitle: \\\"300 hours of Speed Boost\\\", localizedPrice: LocalizedPrice.localizedPrice(price: 29.99, priceLocale: PriceLocale(locale: \\\"(en_CA@currency=CAD (fixed)\\\")), clearedForSale: true)), ParsedPsiCashAppStorePurchasable.purchasable(PsiCashPurchasableViewModel(product: PsiCashPurchasableViewModel.ProductType.product(AppStoreProduct(type: psiCash, productID: \\\"ca.psiphon.Consumable.PsiCash.100000\\\", localizedDescription: \\\"1000 hours of Speed Boost\\\", price: localizedPrice(price: 99.99, priceLocale: PriceLocale(locale: \\\"(en_CA@currency=CAD (fixed)\\\")))), title: \\\"100,000\\\", subtitle: \\\"1000 hours of Speed Boost\\\", localizedPrice: LocalizedPrice.localizedPrice(price: 99.99, priceLocale: PriceLocale(locale: \\\"(en_CA@currency=CAD (fixed)\\\")), clearedForSale: true))])), psiCashRequest: nil), pendingLandingPageOpening: false, internetReachability: ReachabilityState(networkStatus: ReachabilityStatus.viaWiFi, codedStatus: \\\"-R -------\\\"), appDelegateState: AppDelegateState(appLifecycle: AppLifecycle.didBecomeActive, adPresentationState: false, pendingPresentingDisallowedTrafficAlert: false), queuedFeedbacks: [UserFeedback([\\\"uploadDiagnostics\\\": true, \\\"submitTime\\\": 2020-11-26 20:20:07 +0000])])".replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "PsiCashClient.", with: ""),

        ]
    }

    static var allTests = [
        ("testAppStateParser", testAppStateParser),
        ("testTypeParser", testTypeParser)
    ]
}
