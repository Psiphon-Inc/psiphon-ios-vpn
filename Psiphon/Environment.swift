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
var Debugging = DebugFlags()
var Current = Environment.debug(flags: Debugging)
#else
var Debugging = DebugFlags.disabled()
var Current = Environment.default()
#endif

var Style = AppStyle()

/// A verified stricter set of `Bundle` properties.
struct PsiphonBundle {
    let bundleIdentifier: String
    let appStoreReceiptURL: URL
    
    /// Validates app's environment give the assumptions made in the app for certain invariants to hold true.
    /// - Note: Stops program execution if any of the vaidations fail.
    static func from(bundle: Bundle) -> PsiphonBundle {
        return PsiphonBundle(bundleIdentifier: bundle.bundleIdentifier!,
                             appStoreReceiptURL: bundle.appStoreReceiptURL!)
    }
}

struct DebugFlags {
    var mainThreadChecks = true
    var disableURLHandler = true
    var devServers = true
    var ignoreTunneledChecks = false
    
    var printStoreLogs = false
    var printAppState = true
    var printHttpRequests = true
    
    static func disabled() -> Self {
        return .init(mainThreadChecks: false,
                     disableURLHandler: false,
                     devServers: false,
                     ignoreTunneledChecks: false,
                     printStoreLogs: false,
                     printAppState: false,
                     printHttpRequests: false)
    }
}

struct Environment {
    var clientMetaData: ClientMetaData
    var objcBridgeDelegate: ObjCBridgeDelegate?
    let priceFormatter: CurrencyFormatter
    let psiCashPriceFormatter: PsiCashAmountFormatter
    let locale: Locale
    let appBundle: PsiphonBundle
    let userConfigs: UserDefaultsConfig
    let sharedDB: PsiphonDataSharedDB
    let notifier: Notifier
    let vpnManager: VPNManager
    let vpnStatus: State<NEVPNStatus>
    let psiCashEffect: PsiCashEffect
    let psiCashLogger: PsiCashLogger
    let paymentQueue: PaymentQueue
    let app: Application
    let urlHandler: URLHandler
    let receiptRefreshDelegate: ReceiptRefreshRequestDelegate
    let paymentTransactionDelegate: PaymentTransactionDelegate
    let rewardedVideoAdBridgeDelegate: RewardedVideoAdBridgeDelegate
    let productRequestDelegate: ProductRequestDelegate
    let hardCodedValues: HardCodedValues
}

extension Environment {
    static let `default`: () -> Environment = {
        let locale = Locale.current
        let psiCashLib = PsiCash()
        let app = Application(initalState: AppState(), reducer: appReducer)
        
        return Environment(
            clientMetaData: ClientMetaData(),
            objcBridgeDelegate: nil,
            priceFormatter: CurrencyFormatter(locale: locale),
            psiCashPriceFormatter: PsiCashAmountFormatter(locale: locale),
            locale: locale,
            appBundle: PsiphonBundle.from(bundle: Bundle.main),
            userConfigs: UserDefaultsConfig(),
            sharedDB: PsiphonDataSharedDB(forAppGroupIdentifier: APP_GROUP_IDENTIFIER),
            notifier: Notifier.sharedInstance(),
            vpnManager: VPNManager.sharedInstance(),
            vpnStatus: VPNStatusBridge.instance.$status,
            psiCashEffect: PsiCashEffect(psiCash: psiCashLib),
            psiCashLogger: PsiCashLogger(client: psiCashLib),
            paymentQueue: .default,
            app: app,
            urlHandler: .default,
            receiptRefreshDelegate: ReceiptRefreshRequestDelegate(store:
                app.store.projection(
                    value: erase,
                    action: { .appReceipt($0) })
            ),
            paymentTransactionDelegate: PaymentTransactionDelegate(store:
                app.store.projection(
                    value: erase,
                    action: { .iap(.transactionUpdate($0)) })
            ),
            rewardedVideoAdBridgeDelegate: SwiftDelegate.instance,
            productRequestDelegate: ProductRequestDelegate(store:
                app.store.projection(
                    value: erase,
                    action: { .productRequest($0) })
            ),
            hardCodedValues: HardCodedValues()
        )
    }
    
    static func debug(flags: DebugFlags) -> Environment {
        let locale = Locale.current
        let psiCashLib = PsiCash()
        let app = Application(initalState: AppState(), reducer: appReducer)
        
        if flags.devServers {
            psiCashLib.setValue("dev-api.psi.cash", forKey: "serverHostname")
        }
        
        return Environment(
            clientMetaData: ClientMetaData(),
            objcBridgeDelegate: nil,
            priceFormatter: CurrencyFormatter(locale: locale),
            psiCashPriceFormatter: PsiCashAmountFormatter(locale: locale),
            locale: locale,
            appBundle: PsiphonBundle.from(bundle: Bundle.main),
            userConfigs: UserDefaultsConfig(),
            sharedDB: PsiphonDataSharedDB(forAppGroupIdentifier: APP_GROUP_IDENTIFIER),
            notifier: Notifier.sharedInstance(),
            vpnManager: VPNManager.sharedInstance(),
            vpnStatus: VPNStatusBridge.instance.$status,
            psiCashEffect: PsiCashEffect(psiCash: psiCashLib),
            psiCashLogger: PsiCashLogger(client: psiCashLib),
            paymentQueue: .default,
            app: app,
            urlHandler: .default,
            receiptRefreshDelegate: ReceiptRefreshRequestDelegate(store:
                app.store.projection(
                    value: erase,
                    action: { .appReceipt($0) })
            ),
            paymentTransactionDelegate: PaymentTransactionDelegate(store:
                app.store.projection(
                    value: erase,
                    action: { .iap(.transactionUpdate($0)) })
            ),
            rewardedVideoAdBridgeDelegate: SwiftDelegate.instance,
            productRequestDelegate: ProductRequestDelegate(store:
                app.store.projection(
                    value: erase,
                    action: { .productRequest($0) })
            ),
            hardCodedValues: HardCodedValues()
        )
    }
    
    var tunneled: Bool {
        if Debugging.ignoreTunneledChecks { return true }
        return self.vpnManager.tunnelProviderStatus == .connected
    }
}
