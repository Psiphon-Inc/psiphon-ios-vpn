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

struct PsiCashViewControllerState: Equatable {
    let psiCashBalance: PsiCashBalance
    let psiCash: PsiCashState
    let iap: IAPState
    let subscription: SubscriptionState
    let appStorePsiCashProducts:
        PendingWithLastSuccess<[ParsedPsiCashAppStorePurchasable], SystemErrorEvent>
}

extension PsiCashViewControllerState {
    
    /// Adds rewarded video product to list of `PsiCashPurchasableViewModel`  retrieved from AppStore.
    func allProducts(
        rewardedVideoClearedForSale: Bool,
        rewardedVideoSubtitle: String
    ) -> PendingWithLastSuccess<[PsiCashPurchasableViewModel], SystemErrorEvent> {
        appStorePsiCashProducts.map(pending: { lastParsedList -> [PsiCashPurchasableViewModel] in
            // Adds rewarded video ad as the first product if
            let viewModels = lastParsedList.compactMap { parsed -> PsiCashPurchasableViewModel? in
                parsed.viewModel
            }
            switch viewModels {
            case []: return []
            default: return [
                psiCash.rewardedVideoProduct(
                    clearedForSale: rewardedVideoClearedForSale, subtitle: rewardedVideoSubtitle
                )
                ] + viewModels
            }
        }, completed: { result in
            result.map { parsedList -> [PsiCashPurchasableViewModel] in
                // Adds rewarded video ad as the first product
                [
                    psiCash.rewardedVideoProduct(
                        clearedForSale: rewardedVideoClearedForSale, subtitle: rewardedVideoSubtitle
                    ) ] + parsedList.compactMap { parsed -> PsiCashPurchasableViewModel? in
                        parsed.viewModel
                }
            }
        })
    }
    
}

final class PsiCashViewController: UIViewController {
    typealias AddPsiCashViewType =
        EitherView<PsiCashCoinPurchaseTable,
        EitherView<Spinner,
        EitherView<PsiCashMessageViewUntunneled,
        EitherView<PsiCashMessageWithRetryView, PsiCashMessageView>>>>

    typealias SpeedBoostViewType = EitherView<SpeedBoostPurchaseTable,
        EitherView<Spinner,
        EitherView<PsiCashMessageViewUntunneled, PsiCashMessageView>>>

    struct ObservedState: Equatable {
        let state: PsiCashViewControllerState
        let activeTab: PsiCashViewController.Tabs
        let tunneled: TunnelConnectedStatus
    }

    enum Screen: Equatable {
        case mainScreen
        case psiCashPurchaseDialog
        case speedBoostPurchaseDialog
    }

    @objc enum Tabs: Int, UICases {
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
    private let store: Store<PsiCashViewControllerState, PsiCashAction>
    private let productRequestStore: Store<Unit, ProductRequestAction>

    // VC-specific UI state
    @State private var activeTab: Tabs
    private var navigation: Screen = .mainScreen

    /// Set of presented error alerts.
    /// Note: Once an error alert has been dismissed by the user, it will be removed from the set.
    private var errorAlerts = Set<ErrorEventDescription<ErrorRepr>>()

    // Views
    private let balanceView = PsiCashBalanceView(frame: .zero)
    private let closeButton = CloseButton(frame: .zero)
    private let tabControl = TabControlView<Tabs>()

    private let container: EitherView<AddPsiCashViewType, SpeedBoostViewType>
    private let containerView = UIView(frame: .zero)
    private let containerBindable: EitherView<AddPsiCashViewType, SpeedBoostViewType>.BuildType

    init(initialTab: Tabs,
         store: Store<PsiCashViewControllerState, PsiCashAction>,
         iapStore: Store<Unit, IAPAction>,
         productRequestStore: Store<Unit, ProductRequestAction>,
         tunnelConnectedSignal: SignalProducer<TunnelConnectedStatus, Never>) {

        self.activeTab = initialTab
        self.store = store
        self.productRequestStore = productRequestStore
        
        self.container = .init(
            AddPsiCashViewType(
                PsiCashCoinPurchaseTable(purchaseHandler: { [unowned store, iapStore] in
                    switch $0 {
                    case .rewardedVideoAd:
                        store.send(.showRewardedVideoAd)
                    case .product(let product):
                        iapStore.send(.purchase(.psiCash(product: product)))
                    }
                }),
                .init(Spinner(style: .whiteLarge),
                      .init(PsiCashMessageViewUntunneled(action: { [unowned store] in
                        store.send(.connectToPsiphonTapped)
                      }), .init(PsiCashMessageWithRetryView(),
                                PsiCashMessageView())))),
            SpeedBoostViewType(
                SpeedBoostPurchaseTable(purchaseHandler: {
                    store.send(.buyPsiCashProduct(.speedBoost($0)))
                }),
                .init(Spinner(style: .whiteLarge),
                      .init(PsiCashMessageViewUntunneled(action: { [unowned store] in
                        store.send(.connectToPsiphonTapped)
                      }), PsiCashMessageView()))))

        containerBindable = self.container.build(self.containerView)

        super.init(nibName: nil, bundle: nil)

        // Updates UI by merging all necessary signals.
        self.lifetime += SignalProducer.combineLatest(
            store.$value.signalProducer,
            self.$activeTab.signalProducer,
            tunnelConnectedSignal)
            .map(ObservedState.init)
            .skipRepeats()
            .startWithValues { [unowned self] observed in
                
                if case let .failure(errorEvent) = observed.state.psiCash.rewardedVideo.loading {
                    switch errorEvent.error {
                    case .adSDKError(_), .requestedAdFailedToLoad:
                        let errorDesc = ErrorEventDescription(
                            event: errorEvent.eraseToRepr(),
                            localizedUserDescription: UserStrings.Rewarded_video_load_failed())

                        self.displayBasicAlert(errorDesc: errorDesc)
                        
                    case .noTunneledRewardedVideoAd:
                        break
                        
                    case .customDataNotPresent:
                        fatalErrorFeedbackLog("Custom data not present")
                    }
                }
                
                let purchasingNavState = (observed.state.iap.purchasing,
                                          observed.state.psiCash.purchasing,
                                          self.navigation)
                
                switch purchasingNavState {
                case (.none, .none, _):
                    self.display(screen: .mainScreen)
                    
                case (.pending(.psiCash(_)), _, .mainScreen):
                    self.display(screen: .psiCashPurchaseDialog)
                    
                case (.pending(.psiCash(_)), _, .psiCashPurchaseDialog):
                    break
                    
                case (_, .speedBoost(_), .mainScreen):
                    self.display(screen: .speedBoostPurchaseDialog)
                    
                case (_, .speedBoost(_), .speedBoostPurchaseDialog):
                    break
                    
                case (_, .error(let psiCashErrorEvent), _):
                    let errorDesc = ErrorEventDescription(
                        event: psiCashErrorEvent.eraseToRepr(),
                        localizedUserDescription: psiCashErrorEvent.error.userDescription
                    )
                    
                    self.display(screen: .mainScreen)
                    
                    if case .serverError(.insufficientBalance, nil) = psiCashErrorEvent.error {
                        self.display(errorDesc: errorDesc) { () -> UIAlertController in
                            let alertController = UIAlertController(
                                title: UserStrings.Error_title(),
                                message: errorDesc.localizedUserDescription,
                                preferredStyle: .alert
                            )

                            alertController.addAction(
                                UIAlertAction(
                                    title: "Add PsiCash",
                                    style: .default,
                                    handler: { [unowned self] _ in
                                        self.activeTab = .addPsiCash
                                })
                            )
                            
                            alertController.addAction(
                                UIAlertAction(title: UserStrings.Dismiss_button_title(),
                                              style: .cancel)
                            )
                            return alertController
                        }
                    } else {
                        self.displayBasicAlert(errorDesc: errorDesc)
                    }
                    
                case (.error(let iapErrorEvent), _, _):
                    self.display(screen: .mainScreen)
                    if let errorDesc = errorEventDescription(iapErrorEvent: iapErrorEvent) {
                        self.displayBasicAlert(errorDesc: errorDesc)
                    }
                    
                default:
                    fatalErrorFeedbackLog("""
                        Invalid purchase navigation state combination: \
                        '\(String(describing: purchasingNavState))',
                        """)
                }
                
                guard observed.state.psiCash.libData.authPackage.hasMinimalTokens else {
                    self.balanceView.isHidden = true
                    self.tabControl.isHidden = true
                    self.containerBindable.bind(
                        .left(.right(.right(.right(.right(.otherErrorTryAgain)))))
                    )
                    return
                }

                switch observed.state.subscription.status {
                case .unknown:
                    // There is not PsiCash state or subscription state is unknown.
                    self.balanceView.isHidden = true
                    self.tabControl.isHidden = true
                    self.containerBindable.bind(
                        .left(.right(.right(.right(.right(.otherErrorTryAgain)))))
                    )

                case .subscribed(_):
                    // User is subscribed. Only shows the PsiCash balance.
                    self.balanceView.isHidden = false
                    self.tabControl.isHidden = true
                    self.balanceView.bind(
                        BalanceState(psiCashState: observed.state.psiCash,
                                     balance: observed.state.psiCashBalance)
                    )
                    self.containerBindable.bind(
                        .left(.right(.right(.right(.right(.userSubscribed)))))
                    )

                case .notSubscribed:
                    self.balanceView.isHidden = false
                    self.tabControl.isHidden = false
                    self.balanceView.bind(
                        BalanceState(psiCashState: observed.state.psiCash,
                                     balance: observed.state.psiCashBalance)
                    )

                    // Updates active tab UI
                    switch observed.activeTab {
                    case .addPsiCash:
                        self.tabControl.bind(.addPsiCash)
                    case .speedBoost:
                        self.tabControl.bind(.speedBoost)
                    }

                    switch (observed.tunneled, observed.activeTab) {
                    case (.notConnected, .addPsiCash),
                         (.connected, .addPsiCash):
                        
                        if let unverifiedPsiCashTx = observed.state.iap.unverifiedPsiCashTx {
                            switch observed.tunneled {
                            case .connected:
                                
                                // Set view content based on verification state of the
                                // unverified PsiCash IAP transaction.
                                switch unverifiedPsiCashTx.verificationState {
                                case .notRequested, .pendingVerificationResult:
                                    self.containerBindable.bind(
                                        .left(.right(.right(.right(.right(
                                            .pendingPsiCashVerification)))))
                                    )
                                    
                                case .requestError(_):
                                    // Shows failed to verify purchase message with,
                                    // tap to retry button.
                                    self.containerBindable.bind(
                                        .left(.right(.right(.right(.left(
                                            .failedToVerifyPsiCashIAPPurchase(retryAction: {
                                                iapStore.send(.checkUnverifiedTransaction)
                                            })))))))
                                }
                                
                            case .notConnected:
                                // If tunnel is not connected and there is a pending PsiCash IAP,
                                // then shows the "pending psicash purchase" screen.
                                self.containerBindable.bind(
                                    .left(.right(.right(.left(.pendingPsiCashPurchase))))
                                )
                            case .connecting, .disconnecting:
                                fatalErrorFeedbackLog("tunnelState at this point should not be 'connecting'")
                            }

                        } else {
                            
                            
                            // Subtitle for rewarded video product given tunneled status.
                            let rewardedVideoClearedForSale: Bool
                            let rewardedVideoSubtitle: String
                            switch observed.tunneled {
                            case .connected:
                                rewardedVideoClearedForSale = false
                                rewardedVideoSubtitle =
                                    UserStrings.Disconnect_from_psiphon_to_watch_and_earn_psicash()
                            case .notConnected:
                                rewardedVideoClearedForSale = true
                                rewardedVideoSubtitle = UserStrings.Watch_rewarded_video_and_earn()
                            case .connecting, .disconnecting:
                                fatalErrorFeedbackLog("Unexpected state")
                            }
                            
                            let allProducts = observed.state.allProducts(
                                rewardedVideoClearedForSale: rewardedVideoClearedForSale,
                                rewardedVideoSubtitle: rewardedVideoSubtitle
                            )
                            
                            switch allProducts {
                            case .pending([]):
                                // Product list is being retrieved from the
                                // App Store for the first time.
                                // A spinner is shown.
                                self.containerBindable.bind(.left(.right(.left(true))))
                            case .pending(let lastSuccess):
                                // Displays product list from previous retrieval.
                                self.containerBindable.bind(.left(.left(lastSuccess)))
                            case .completed(let productRequestResult):
                                // Product list retrieved from App Store.
                                switch productRequestResult {
                                case .success(let psiCashCoinProducts):
                                    self.containerBindable.bind(.left(.left(psiCashCoinProducts)))
                                case .failure(_):
                                    // Shows failed to load message with tap to retry button.
                                    self.containerBindable.bind(
                                        .left(.right(.right(.right(.left(
                                            .failedToLoadProductList(retryAction: {
                                                productRequestStore.send(.getProductList)
                                            })))))))
                                }
                            }
                        }

                    case (.connecting, _):
                        self.tabControl.isHidden = true
                        self.containerBindable.bind(
                            .left(.right(.right(.right(.right(.unavailableWhileConnecting))))))
                    
                    case (.disconnecting, _):
                        self.tabControl.isHidden = true
                        self.containerBindable.bind(
                        .left(.right(.right(.right(.right(.unavailableWhileDisconnecting))))))

                    case (let tunnelState, .speedBoost):

                        let activeSpeedBoost = observed.state.psiCash.activeSpeedBoost
                        
                        switch tunnelState {
                        case .notConnected, .connecting, .disconnecting:

                            switch activeSpeedBoost {
                            case .none:
                                // There is no active speed boost.
                            let connectToPsiphonMessage =
                                PsiCashMessageViewUntunneled.Message
                                    .speedBoostUnavailable(subtitle: .connectToPsiphon)

                            self.containerBindable.bind(
                                .right(.right(.right(.left(connectToPsiphonMessage)))))

                            case .some(_):
                                // There is an active speed boost.
                                self.containerBindable.bind(
                                    .right(.right(.right(.left(.speedBoostAlreadyActive)))))
                            }


                        case .connected:
                            switch activeSpeedBoost {
                            case .none:
                                // There is no active speed boost.
                                let viewModel = NonEmpty(array:
                                    observed.state.psiCash.libData.availableProducts
                                .items.compactMap { $0.speedBoost }
                                .map { SpeedBoostPurchasableViewModel(purchasable: $0) })

                                if let viewModel = viewModel {
                                self.containerBindable.bind(.right(.left(viewModel)))
                                } else {
                                let tryAgainLater = PsiCashMessageViewUntunneled.Message
                                .speedBoostUnavailable(subtitle: .tryAgainLater)
                                self.containerBindable.bind(
                                .right(.right(.right(.left(tryAgainLater)))))
                                }

                            case .some(_):
                                // There is an active speed boost.
                                // There is an active speed boost.
                                self.containerBindable.bind(
                                    .right(.right(.right(.right(.speedBoostAlreadyActive)))))
                            }
                        }
                    }
                }
        }
    }

    required init?(coder: NSCoder) {
        fatalErrorFeedbackLog("init(coder:) has not been implemented")
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
        productRequestStore.send(.getProductList)
    }

}

// Navigations
extension PsiCashViewController {

    /// Display an error alert with a single "OK" button.
    private func displayBasicAlert(errorDesc: ErrorEventDescription<ErrorRepr>) {

        self.display(errorDesc: errorDesc) { () -> UIAlertController in
            let alert = UIAlertController(title: UserStrings.Error_title(),
                                          message: errorDesc.localizedUserDescription,
                                          preferredStyle: .alert)

            alert.addAction(
                UIAlertAction(title: UserStrings.OK_button_title(), style: .default)
            )
            
            return alert
        }
    }
    
    /// Display error alert if `errorDesc` is a unique alert not in `self.errorAlerts`.
    /// Only if the error is unique `makeAlertController` is called for creating the alert controller.
    private func display(errorDesc: ErrorEventDescription<ErrorRepr>,
                         makeAlertController: () -> UIAlertController) {
        // Inserts `errorDesc` into `errorAlerts` set.
        // If a member of `errorAlerts` is equal to `errorDesc.event.error`, then
        // that member is removed and `errorDesc` is inserted.
        let inserted = self.errorAlerts.insert(orReplaceIfEqual: \.event.error, errorDesc)

        // Prevent display of the same error event.
        guard inserted else {
            return
        }
        
        let alertController = makeAlertController()
        self.present(alertController, animated: true, completion: nil)
    }

    private func display(screen: Screen) {
        guard self.navigation != screen else {
            return
        }
        self.navigation = screen

        switch screen {
        case .mainScreen:
            self.presentedViewController?.dismiss(animated: false, completion: nil)

        case .psiCashPurchaseDialog:
            let purchasingViewController = AlertViewController(viewBuilder:
                PsiCashPurchasingViewBuilder())

            self.present(purchasingViewController, animated: false,
                                             completion: nil)

        case .speedBoostPurchaseDialog:
            let vc = AlertViewController(viewBuilder: PurchasingSpeedBoostAlertViewBuilder())
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

fileprivate func errorEventDescription(
    iapErrorEvent: ErrorEvent<IAPError>
) -> ErrorEventDescription<ErrorRepr>? {
    let optionalDescription: String?
    switch iapErrorEvent.error {
    case let .failedToCreatePurchase(reason: reason):
        optionalDescription = reason
    case let .storeKitError(error: error):
        // Payment cancelled errors are ignored.
        if case let .left(skError) = error, skError.code == .paymentCancelled {
            optionalDescription = .none
        } else {
            optionalDescription = """
            \(UserStrings.Purchase_failed())
            (\(error.localizedDescription))
            """
        };
    }
    
    guard let description = optionalDescription else {
        return nil
    }
    return ErrorEventDescription(event: iapErrorEvent.eraseToRepr(),
                                 localizedUserDescription: description)
}
