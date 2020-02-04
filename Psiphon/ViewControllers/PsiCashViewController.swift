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
import UIKit
import ReactiveCocoa
import ReactiveSwift
import Promises
import StoreKit

typealias PurchaseResult = Result<(), ErrorEvent<PurchaseError>>

enum PurchaseError: HashableError {
    case failedToCreatePurchase(reason: String)
    case purchaseRequestError(error: IAPError)
}

enum PurchasingState: Equatable {
    case psiCash
    case speedBoost(SpeedBoostPurchasable)
    case iapError(ErrorEvent<PurchaseError>)
    case psiCashError(ErrorEvent<PsiCashPurchaseResponseError>)
}

typealias RewardedVideoPresentation = AdPresentation
typealias RewardedVideoLoad = Result<AdLoadStatus, ErrorEvent<ErrorRepr>>

struct RewardedVideoState: Equatable {
    var loading: RewardedVideoLoad = .success(.none)
    var presentation: RewardedVideoPresentation = .didDisappear
    var dismissed: Bool = false
    var rewarded: Bool = false

    var isLoading: Bool {
        switch loading {
        case .success(.inProgress): return true
        default: return false
        }
    }

    var rewardedAndDismissed: Bool {
        return dismissed && rewarded
    }
}

enum PsiCashAction {
    // TODO: Wrap SKProduct in a type-safe container.
    case psiCashCoinProductList(ReqRes<(), Result<[SKProduct], SystemErrorEvent>>)
    case buyPsiCashCoin(ReqRes<SKProduct, PurchaseResult>)
    case buyPsiCashProduct(ReqRes<PsiCashPurchasableType, PsiCashPurchaseResult>)
    case showRewardedVideoAd
    case rewardedVideoPresentation(RewardedVideoPresentation)
    case rewardedVideoLoad(RewardedVideoLoad)
    case connectToPsiphonTapped
    case dismissedAlert(PsiCashAlertDismissAction)
}

enum PsiCashAlertDismissAction {
    case psiCashCoinPurchase
    case rewardedVideo
    case speedBoostAlreadyActive
}

func psiCashReducer(
    state: inout PsiCashState, action: PsiCashAction
) -> [EffectType<PsiCashAction, Application.ExternalAction>] {
    switch action {
    case .psiCashCoinProductList(let reqres):
        switch reqres {
        case .request:
            state.psiCashIAPProducts = .inProgress
            return [.internal(
                appStoreProductRequest(productIds: .psiCash()).map { result -> PsiCashAction in
                    return .psiCashCoinProductList(.response(result))
            })]
        case .response(let result):
            state.psiCashIAPProducts = ProgressiveResult.from(result: result.map {
                $0.map { skProduct in
                    PsiCashPurchasableViewModel.from(skProduct: skProduct)
                }
            })
            return []
        }

    case .buyPsiCashCoin(let reqres):
        switch reqres {
        case let .request(product):
            guard state.purchasing == .none else {
                return []
            }
            guard let appStoreProduct = AppStoreProduct(product) else {
                // TODO: show an error to the user saying this product is unknown
                // TODO: Refresh product request.
                // TODO: write log to feedback.
                return []
            }
            state.purchasing = .psiCash
            let purchasePromise = Promise<PurchaseResult>.pending()
            let customDataPromise = Promise<CustomData?>.pending()

            return [
                .external(.action(.psiCash(.rewardedVideoCustomData(customDataPromise)))),
                .external(Effect(promise: customDataPromise, then:
                    { [appStoreProduct, purchasePromise] in
                        // TODO: How to guarantee that purchasePromise.fullfil
                        // is called in all branches of this scope?
                        guard let customData = $0 else {
                            purchasePromise.fulfill(.failure(
                                ErrorEvent(.failedToCreatePurchase(
                                    reason: "PsiCash data not present."))))
                            return nil
                        }
                        let purchasable = PurchasableProduct.psiCash(product: appStoreProduct,
                                                                     customData: customData)
                        // TODO: Check promise ref
                        let promise = Promise<IAPResult>.pending()
                        promise.then { resolution in
                            let newResolution = resolution.result.mapError { iapErrorEvent in
                                iapErrorEvent.map { iapError -> PurchaseError in
                                    .purchaseRequestError(error: iapError)
                                }
                            }
                            purchasePromise.fulfill(newResolution)
                        }
                        return .actor(.inAppPurchase(.buyProduct(purchasable, promise)))
                })),
                .internal(Effect<PsiCashAction>(promise: purchasePromise, then: {
                    .buyPsiCashCoin(.response($0))
                }))]

        case let .response(purchaseResult):
            switch purchaseResult {
            case .success:
                state.purchasing = .none
            case .failure(let error):
                state.purchasing = .iapError(error)
            }
            return []
        }

    case .buyPsiCashProduct(let reqres):
        switch reqres {
        case .request(let purchasableType):

            guard state.purchasing == .none else {
                return []
            }

            guard let purchasable = purchasableType.speedBoost else {
                fatalError()
            }

            state.purchasing = .speedBoost(purchasable)

            let promise = Promise<PsiCashPurchaseResult>.pending()

            return [.external(.action(.psiCash(.purchase(purchasableType, promise)))),
                    .internal(Effect<PsiCashAction>(promise: promise, then: {
                        .buyPsiCashProduct(.response($0))
                    }))
            ]

        case .response(let purchaseResult):
            guard case .speedBoost = state.purchasing else {
                fatalError("Expected '.speedBoost' state:'\(String(describing: state.purchasing))'")
            }

            guard purchaseResult.purchasable.speedBoost != nil else {
                fatalError("Expected '.speedBoost'; purchasable: '\(purchaseResult.purchasable)'")
            }
            
            switch purchaseResult.purchasedResult {
            case .success(let purchasedType):
                guard case .speedBoost = purchasedType else {
                    fatalError("Expected '.speedBoost' purchaesd type")
                }
                state.purchasing = .none
                return [.external(.objc(.dismiss(.psiCash)))]

            case .failure(let errorEvent):
                state.purchasing = .psiCashError(errorEvent)
                return []
            }
        }

    case .showRewardedVideoAd:
        let rewardAdCustomData = Promise<CustomData?>.pending()
        return [.external(.action(.psiCash(.rewardedVideoCustomData(rewardAdCustomData)))),
                .external(Effect<Application.ExternalAction>(promise: rewardAdCustomData, then: {
                    guard let customData = $0 else {
                        return nil
                    }
                    return .objc(.presentRewardedVideoAd(customData: customData))
                }))]

    case .rewardedVideoPresentation(let presentation):
        state.rewardedVideo.combine(presentation: presentation)

        if state.rewardedVideo.rewardedAndDismissed {

            let rewardAmount = Current.hardCodedValues.psiCashRewardValue

            let refreshWithRetryEffect = SignalProducer<Application.ExternalAction, ErrorEvent<PsiCashRefreshError>>{ observer, _ in
                let promise = Promise<Result<(), ErrorEvent<PsiCashRefreshError>>>.pending()
                observer.send(value: .actor(.psiCash(.refreshState(reason: .rewardedVideoAd, promise: promise))))
                promise.then { result in
                    if let error = result.projectError() {
                        observer.send(error: error)
                    } else {
                        observer.sendCompleted()
                    }
                }
            }
            .retry(upTo: 10, interval: 1.0, on: QueueScheduler.main)
            .flatMapError{ _ -> SignalProducer<Application.ExternalAction, Never> in
                return .empty
            }

            return [
                .external(.action(.psiCash(.receivedRewardedVideoReward(amount: rewardAmount)))),
                    .external(Effect(refreshWithRetryEffect))
            ]
        } else {
            return []
        }

    case .rewardedVideoLoad(let loadStatus):
        state.rewardedVideo.combine(loading: loadStatus)
        return []

    case .dismissedAlert(let dismissed):
        switch dismissed {
        case .psiCashCoinPurchase, .speedBoostAlreadyActive:
            state.purchasing = .none
            return []
        case .rewardedVideo:
            state.rewardedVideo.combineWithErrorDismissed()
            return []
        }

    case .connectToPsiphonTapped:
        return [.external(.objc(.connectTunnel)),
                .external(.objc(.dismiss(.psiCash)))]
    }
}
// MARK: ViewController

final class PsiCashViewController: UIViewController {
    typealias AddPsiCashViewType = EitherView<PsiCashCoinPurchaseTable,
        EitherView<Spinner, PsiCashUnavailable>>

    typealias SpeedBoostViewType = EitherView<SpeedBoostPurchaseTable,
        EitherView<Spinner, SpeedBoostUnavailable_ViewBuilder>>

    struct ObservedState: Equatable {
        let actorState: PsiCashActor.State?
        let state: PsiCashState
        let activeTab: PsiCashViewController.UITab
        let vpnStatus: NEVPNStatus
    }

    enum Screen: Equatable {
        case mainScreen
        case psiCashPurchaseScreen
        case speedBoostPurchaseDialog
        case speedBoostAlreadyActiveAlert
    }

    enum UITab: UICases {
        case addPsiCash
        case speedBoost

        var description: String {
            switch self {
            case .addPsiCash: return UserStrings.Add_psiCash()
            case .speedBoost: return UserStrings.Speed_boost()
            }
        }
    }

    private let (lifetime, token) = Lifetime.make()
    private let store: Store<PsiCashState, PsiCashAction, Application.ExternalAction>

    // VC-specific UI state
    @State private var activeTab: UITab = .speedBoost
    private var navigation: Screen = .mainScreen

    /// Set of presented error alerts.
    /// Note: Once an error alert has been dismissed by the user, it will be removed from the set.
    private var errorAlerts = Set<ErrorEventDescription<ErrorRepr>>()

    // Views
    private let balanceView = PsiCashBalanceView(frame: .zero)
    private let closeButton = CloseButton(frame: .zero)
    private let tabControl = TabControlView<UITab>()

    private let container: EitherView<AddPsiCashViewType, SpeedBoostViewType>
    private let containerView = UIView(frame: .zero)
    private let containerBindable: EitherView<AddPsiCashViewType, SpeedBoostViewType>.BuildType

    init(store: Store<PsiCashState, PsiCashAction, Application.ExternalAction>,
         actorStateSignal: SignalProducer<PsiCashActor.State?, Never>) {

        self.store = store
        self.container = .init(
            AddPsiCashViewType(
                PsiCashCoinPurchaseTable(purchaseHandler: {
                    switch $0 {
                    case .rewardedVideoAd:
                        store.send(.showRewardedVideoAd)
                    case .product(let skProduct):
                        store.send(.buyPsiCashCoin(.request(skProduct)))
                    }
                }),
                .init(Spinner(style: .whiteLarge),
                      PsiCashUnavailable())),
            SpeedBoostViewType(
                SpeedBoostPurchaseTable(purchaseHandler: {
                    store.send(.buyPsiCashProduct(.request(.speedBoost($0))))
                }),
                .init(Spinner(style: .whiteLarge),
                      SpeedBoostUnavailable_ViewBuilder(
                        action: { [unowned store] in
                            store.send(.connectToPsiphonTapped)
                      }))))

        containerBindable = self.container.build(self.containerView)

        super.init(nibName: nil, bundle: nil)

        // Updates UI by merging all necessary signals.
        self.lifetime += SignalProducer.combineLatest(
            actorStateSignal,
            store.$value.signalProducer,
            self.$activeTab.signalProducer,
            Current.vpnStatus.signalProducer)
            .map(ObservedState.init)
            .skipRepeats()
            .startWithValues { [unowned self] observed in
                let tunnelState = TunnelConnected.from(vpnStatus: observed.vpnStatus)

                if case let .failure(errorEvent) = observed.state.rewardedVideo.loading {
                    let errorDesc = ErrorEventDescription(
                        event: errorEvent,
                        localizedUserDescription: UserStrings.Rewarded_video_load_failed())

                    self.display(errorDesc: errorDesc, onDismiss: .rewardedVideo)
                }

                // TODO: nagivation. This should probably be factored out as an external effect.
                switch (observed.state.purchasing, self.navigation) {
                case (.none, _):
                    if self.navigation != .mainScreen {
                        self.display(screen: .mainScreen)
                    }
                case (.psiCash, .mainScreen):
                    self.display(screen: .psiCashPurchaseScreen)

                case (.psiCash, .psiCashPurchaseScreen):
                    break

                case (.speedBoost, .mainScreen):
                    self.display(screen: .speedBoostPurchaseDialog)

                case (.speedBoost, .speedBoostPurchaseDialog):
                    break

                case (.psiCashError(let errorEvent), _):

                    if case .serverError(.existingTransaction, _) = errorEvent.error {
                        self.display(screen: .speedBoostAlreadyActiveAlert)
                    } else {
                        let errorDesc = ErrorEventDescription(
                            event: errorEvent.eraseToRepr(),
                            localizedUserDescription: errorEvent.error.userDescription
                        )

                        self.display(errorDesc: errorDesc, onDismiss: .speedBoostAlreadyActive)
                    }

                case (.iapError(let errorEvent), _):
                    let description: String
                    switch errorEvent.error {
                    case let .failedToCreatePurchase(reason: reason):
                        description = reason
                    case let .purchaseRequestError(error: iapError):
                        switch iapError {
                        case .waitingForPendingTransactions:
                            description = """
                            There is already a pending PsiCash purchase, \
                            please connect to finish the transaction.
                            """ // TODO: Translate error.
                        case .storeKitError(let storeKitError):
                            description = "Purchase Failed (\(storeKitError.localizedDescription))"
                        }
                    }

                    let errorDesc = ErrorEventDescription(event: errorEvent.eraseToRepr(),
                                                          localizedUserDescription: description)
                    self.display(errorDesc: errorDesc, onDismiss: .psiCashCoinPurchase)

                default:
                    fatalError("""
                        Invalid navigation state 'state.purchasing: \
                        \(String(describing: observed.state.purchasing))', \
                        'navigation: \(self.navigation)'
                        """)
                }

                switch observed.actorState {
                case .none:
                    self.balanceView.isHidden = true
                    self.tabControl.isHidden = true
                    self.containerBindable.bind(.left(.right(.right(.otherErrorTryAgain))))

                case .some(let psiCashActorState):
                    self.balanceView.isHidden = false
                    self.tabControl.isHidden = false
                    self.balanceView.bind(psiCashActorState.balanceState)

                    // Updates active tab UI
                    switch observed.activeTab {
                    case .addPsiCash: self.tabControl.bind(.addPsiCash)
                    case .speedBoost: self.tabControl.bind(.speedBoost)
                    }

                    switch (tunnelState, observed.activeTab) {
                    case (.notConnected, .addPsiCash),
                         (.connected, .addPsiCash):

                        switch observed.state.allProducts {
                        case .inProgress:
                            self.containerBindable.bind(.left(.right(.left(true))))
                        case .completed(let productRequestResult):
                            switch productRequestResult {
                            case .success(let psiCashCoinProducts):
                                self.containerBindable.bind(.left(.left(psiCashCoinProducts)))
                            case .failure(_):
                                self.containerBindable.bind(
                                    .left(.right(.right(.otherErrorTryAgain))))
                            }
                        }

                    case (.connecting, .addPsiCash):
                        self.containerBindable.bind(
                            .left(.right(.right(.unavailableWhileConnecting))))

                    case (.notConnected, .speedBoost), (.connecting, .speedBoost):
                        let connectToPsiphonMessage =
                            SpeedBoostUnavailable_ViewBuilder.Message(
                                subtitle: UserStrings.Connect_to_psiphon_to_use_speed_boost())
                        self.containerBindable.bind(.right(.right(.right(connectToPsiphonMessage))))

                    case (.connected, .speedBoost):
                        let viewModel = NonEmpty(array:
                            psiCashActorState.libData.availableProducts
                                .items.compactMap { $0.speedBoost }
                                .map { SpeedBoostPurchasableViewModel(purchasable: $0) })

                        if let viewModel = viewModel {
                            self.containerBindable.bind(.right(.left(viewModel)))
                        } else {
                            let tryAgainLater =
                                SpeedBoostUnavailable_ViewBuilder.Message(subtitle:
                                    UserStrings.Please_try_again_later())
                            self.containerBindable.bind(.right(.right(.right(tryAgainLater))))


                        }
                    }
                }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        Style.default.statusBarStyle
    }

    // Setup and add all the views here
    override func viewDidLoad() {
        setBackgroundGradient(for: view)

        tabControl.setTabHandler { [unowned self] tab in
            self.activeTab = tab
        }

        closeButton.setEventHandler { [unowned self] in
            self.dismiss(animated: true, completion: nil)
        }

        // Add subviews
        view.addSubview(balanceView)
        view.addSubview(closeButton)
        view.addSubview(tabControl)
        view.addSubview(containerView)

        // Setup layout guide
        let rootViewLayoutGuide = addSafeAreaLayoutGuide(to: view)

        let paddedLayoutGuide = UILayoutGuide()
        view.addLayoutGuide(paddedLayoutGuide)

        paddedLayoutGuide.activateConstraints {
            $0.constraint(to: rootViewLayoutGuide, .top(), .bottom(), .centerX()) +
                [ $0.widthAnchor.constraint(equalTo: rootViewLayoutGuide.widthAnchor,
                                            multiplier: 0.91) ]
        }

        // Setup subview constraints
        setChildrenAutoresizingMaskIntoConstraintsFlagToFalse(forView: view)

        balanceView.activateConstraints {
            $0.constraint(to: paddedLayoutGuide, .centerX(), .top(30))
        }

        closeButton.activateConstraints {[
            $0.centerYAnchor.constraint(equalTo: balanceView.centerYAnchor),
            $0.trailingAnchor.constraint(equalTo: paddedLayoutGuide.trailingAnchor),
            ]}

        tabControl.activateConstraints {[
            $0.topAnchor.constraint(equalTo: balanceView.topAnchor, constant: 50.0),
            $0.centerXAnchor.constraint(equalTo: paddedLayoutGuide.centerXAnchor),
            $0.widthAnchor.constraint(equalTo: paddedLayoutGuide.widthAnchor),
            $0.heightAnchor.constraint(equalToConstant: 44.0)
            ]}

        containerView.activateConstraints {
            $0.constraint(to: paddedLayoutGuide, .bottom(), .leading(), .trailing()) +
                [ $0.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 15.0) ]
        }

    }

    override func viewWillAppear(_ animated: Bool) {
        store.send(.psiCashCoinProductList(.request(())))
    }

}

// Navigations
extension PsiCashViewController {

    private func display(
        errorDesc: ErrorEventDescription<ErrorRepr>,
        onDismiss dismissAction: PsiCashAlertDismissAction
    ) {
        let (inserted, _) = self.errorAlerts.insert(errorDesc)

        // Prevent display of the same error event.
        guard inserted else {
            return
        }

        let alert = UIAlertController(title: UserStrings.Error_title(),
                                      message: errorDesc.localizedUserDescription,
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: UserStrings.OK_button_title(), style: .default)
        { [unowned self, errorDesc] _ in
            self.errorAlerts.remove(errorDesc)
            self.store.send(.dismissedAlert(dismissAction))
        })

        self.topMostController().present(alert, animated: true, completion: nil)
    }

    private func display(screen: Screen) {
        guard self.navigation != screen else {
            return
        }
        self.navigation = screen

        switch screen {
        case .mainScreen:
            self.presentedViewController?.dismiss(animated: false, completion: nil)

        case .psiCashPurchaseScreen:
            let purchasingViewController = AlertViewController(viewBuilder:
                PsiCashPurchasingViewBuilder())

            self.topMostController().present(purchasingViewController, animated: false,
                                             completion: nil)

        case .speedBoostPurchaseDialog:
            let vc = AlertViewController(viewBuilder: PurchasingSpeedBoostAlertViewBuilder())
            self.present(vc, animated: false, completion: nil)

        case .speedBoostAlreadyActiveAlert:
            // Dismisses any alert currently presented, before displaying new alert.
            self.presentedViewController?.dismiss(animated: false, completion: nil)
            let vc = AlertViewController(viewBuilder:
                SpeedBoostActiveAlertViewBuilder(dimissHandler: { [unowned self] in
                    self.store.send(.dismissedAlert(.speedBoostAlreadyActive))
                }))
            self.present(vc, animated: false, completion: nil)
        }
    }

}

// MARK: Extensions

extension RewardedVideoState {
    mutating func combineWithErrorDismissed() {
        guard case .failure(_) = self.loading else {
            return
        }
        self.loading = .success(.none)
    }

    mutating func combine(loading: RewardedVideoLoad) {
        self.loading = loading
    }

    mutating func combine(presentation: RewardedVideoPresentation) {
        self.presentation = presentation
        switch presentation {
        case .didDisappear:
            dismissed = true
        case .didRewardUser:
            rewarded = true
        case .willDisappear:
            return
        case .willAppear,
             .didAppear,
             .errorNoAdsLoaded,
             .errorFailedToPlay,
             .errorCustomDataNotSet,
             .errorInappropriateState:
            fallthrough
        @unknown default:
            dismissed = false
            rewarded = false
        }
    }
}
