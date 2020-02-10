/*
 * Copyright (c) 2019, Psiphon Inc.
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
import SwiftActors
import ReactiveSwift

// MARK: Environment

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

struct Debugging {
    var mainThreadChecks = true
    var disableLandingPage = true
    var psiCashDevServer = true
    var ignoreTunneledChecks = false

    var printStoreLogs = false
    var printActorState = false
    var printAppState = false
    var printHttpRequests = true

    // TODO: Replace with a Debug toolbox button to finish all pending transactions.
    var immediatelyFinishAllIAPTransaction = false

    static func disabled() -> Debugging {
        return .init(mainThreadChecks: false,
                     disableLandingPage: false,
                     psiCashDevServer: false,
                     ignoreTunneledChecks: false,
                     printStoreLogs: false,
                     printActorState: false,
                     printAppState: false,
                     printHttpRequests: false,
                     immediatelyFinishAllIAPTransaction: false)
    }
}

struct HardCodedValues {
    var psiCashRewardValue = PsiCashAmount(nanoPsi: Int64(35e9))
    var psiCashRewardTitle = "35 PsiCash"
}

struct Environment {
    #if DEBUG
    var debugging = Debugging()
    #else
    var debugging = Debugging.disabled()
    #endif
    lazy var priceFormatter = CurrencyFormatter(locale: self.locale)
    lazy var psiCashPriceFormatter = PsiCashAmountFormatter(locale: self.locale)
    lazy var clientMetaData = ClientMetaData.jsonData()
    var locale = Locale.current
    var appBundle = PsiphonBundle.from(bundle: Bundle.main)
    var userConfigs = UserDefaultsConfig()
    var sharedDB = PsiphonDataSharedDB(forAppGroupIdentifier: APP_GROUP_IDENTIFIER)
    var actorBuilder = DefaultActorBuilder()
    var notifier = Notifier.sharedInstance()
    var vpnManager = VPNManager.sharedInstance()
    var vpnStatus: State<NEVPNStatus> = VPNStatusBridge.instance.$status
    var tunneled: Bool {
        if debugging.ignoreTunneledChecks { return true }
        return self.vpnManager.tunnelProviderStatus == .connected
    }
    var hardCodedValues = HardCodedValues()
}

var Current = Environment()
var Style = AppStyle()

// MARK: UIState

/// Represents UIViewController's that can be dismissed.
@objc enum DismissableScreen: Int {
    case psiCash
}

struct PsiCashState: Equatable {
    var rewardedVideo: RewardedVideoState
    var purchasing: PurchasingState?
    var psiCashIAPProducts: ProgressiveResult<[PsiCashPurchasableViewModel], SystemErrorEvent>
}

extension PsiCashState {
    init() {
        rewardedVideo = .init()
        purchasing = .none
        psiCashIAPProducts = .inProgress
    }

    func inProgressIfNoPsiCashIAPProducts() -> ProgressiveResult<[PsiCashPurchasableViewModel], SystemErrorEvent> {
        if case .completed(.success(let previousState)) = psiCashIAPProducts {
            if previousState.count > 0 {
                return psiCashIAPProducts
            }
        }
        return .inProgress
    }

    var rewardedVideoProduct: PsiCashPurchasableViewModel {
        PsiCashPurchasableViewModel(
            product: .rewardedVideoAd(loading: self.rewardedVideo.isLoading),
            title: Current.hardCodedValues.psiCashRewardTitle,
            subtitle: UserStrings.Watch_rewarded_video_and_earn(),
            price: 0.0)
    }

    var allProducts: ProgressiveResult<[PsiCashPurchasableViewModel], SystemErrorEvent> {
        guard case let .completed(productRequestResult) = psiCashIAPProducts else {
            return .inProgress
        }
        switch productRequestResult {
        case .success(let iapProducts):
            return .from(result: .success([rewardedVideoProduct] + iapProducts))
        case .failure(let errorEvent):
            return .completed(.failure(errorEvent))
        }
    }
}

struct UIState: Equatable {
    var psiCash: PsiCashState
}
 
// MARK: AppAction

enum AppAction {
    case objcEffectAction(ObjcEffectAction)
    case psiCash(PsiCashAction)
}

// MARK: Application

let appReducer: Reducer<UIState, AppAction, Application.ExternalAction> =
    combine(
        pullback(psiCashReducer, value: \UIState.psiCash, action: \AppAction.psiCash),
        appDelegateReducer
)

/// Represents an application that has finished loading.
final class Application {
    private let actorSystem = ActorSystem(name: "system")

    enum ExternalAction {
        case actor(AppRootActor.Action)
        case objc(ObjcAction)
    }

    enum ObjcAction {
        case presentRewardedVideoAd(customData: String)
        case connectTunnel
        case dismiss(DismissableScreen)
    }

    // TODO: Make `appRoot` private.
    var appRoot = ObservableActor<AppRootActor, AppRootActor.Action>()
    private(set) var store: Store<UIState, AppAction, ExternalAction>
    private let (lifetime, token) = Lifetime.make()

    /// SignalProducer is observed on the UIScheduler.
    let actorOutput: SignalProducer<AppRootActor.State, Never>

    /// - Parameter objcHandler: Handles `ObjcAction` type. Always called from the main thread.
    init(initialValue: UIState,
         reducer: @escaping Reducer<UIState, AppAction, ExternalAction>,
         objcEffectHandler: @escaping (ObjcAction) -> Void) {

        self.store = Store(
            initialValue: initialValue,
            reducer: reducer,
            external: { [unowned appRoot] value in
                switch value {
                case .actor(let msg):
                    appRoot.actor? ! msg
                case .objc(let objcAction):
                    if Current.debugging.mainThreadChecks {
                        precondition(Thread.isMainThread,
                                     "objcHandler should only be sent from the main thread")
                    }
                    objcEffectHandler(objcAction)
                }
        })

        self.actorOutput = SignalProducer.init(self.appRoot.output)
            .replayLazily(upTo: 1)
            .observeOnUIScheduler()

        self.appRoot.create(
            Current.actorBuilder,
            parent: self.actorSystem,
            transform: id,
            propsBuilder: { input -> Props<AppRootActor> in
                Props(AppRootActor.self,
                      param: AppRootActor.Params(pipeOut: input),
                      qos: .userInteractive)
        })

        if Current.debugging.printActorState {
            lifetime += actorOutput.skipRepeats().startWithValues { actorState in
                print("ActorState:", actorState)
            }
        }

        if Current.debugging.printAppState {
            lifetime += Current.vpnStatus.signalProducer.startWithValues { vpnStatus in
                print("VPNStatus:", vpnStatus.rawValue)
            }
        }
    }

}

extension Effect where A == Application.ExternalAction {

    /// External effect type that sends provided value as a message to `AppRootActor`.
    static func action(_ value: AppRootActor.Action) -> Self {
        return Effect(SignalProducer(value: .actor(value)))
    }

    static func objc(_ value: Application.ObjcAction) -> Self {
        return Effect(SignalProducer(value: .objc(value)))
    }

}

extension Effect where A == AppAction {

    static func action(_ value: AppAction) -> Self {
        return Effect(SignalProducer(value: value))
    }

}
