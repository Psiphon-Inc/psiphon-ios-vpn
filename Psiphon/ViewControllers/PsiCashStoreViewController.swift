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
import ReactiveSwift
import Promises
import StoreKit
import PsiApi
import Utilities
import AppStoreIAP
import PsiCashClient

final class PsiCashStoreViewController: ReactiveViewController {
    
    typealias AddPsiCashViewType =
        EitherView<PsiCashCoinPurchaseTable,
                   EitherView<Spinner,
                              EitherView<PsiCashMessageViewWithButton,
                                         EitherView<PsiCashMessageWithRetryView,
                                                    PsiCashMessageView>>>>
    
    typealias SpeedBoostViewType = EitherView<SpeedBoostPurchaseTable,
                                              EitherView<Spinner,
                                                         EitherView<PsiCashMessageViewWithButton,
                                                                    PsiCashMessageView>>>
    
    typealias ContainerViewType = EitherView<AddPsiCashViewType, SpeedBoostViewType>

    struct ReaderState: Equatable {
        let mainViewState: MainViewState
        let psiCashBalanceViewModel: PsiCashBalanceViewModel
        let psiCash: PsiCashState
        let iap: IAPState
        let subscription: SubscriptionState
        let appStorePsiCashProducts:
            PendingWithLastSuccess<[ParsedPsiCashAppStorePurchasable], SystemErrorEvent<Int>>
        let isRefreshingAppStoreReceipt: Bool
    }

    enum ViewControllerAction {
        case psiCashAction(PsiCashAction)
        case mainViewAction(MainViewAction)
    }
    
    struct ObservedState: Equatable {
        let readerState: ReaderState
        let tunneled: TunnelConnectedStatus
        let lifeCycle: ViewControllerLifeCycle
    }
    
    enum DialogScreen: Equatable {
        case psiCashPurchaseDialog
        case speedBoostPurchaseDialog
    }

    private let platform: Platform
    private let locale: Locale
    private let feedbackLogger: FeedbackLogger
    private let dateCompare: DateCompare
    private let tunnelConnectedSignal: SignalProducer<TunnelConnectedStatus, Never>
    
    private let tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    
    private let (lifetime, token) = Lifetime.make()
    private let store: Store<ReaderState, ViewControllerAction>
    private let iapStore: Store<Utilities.Unit, IAPAction>
    
    private let productRequestStore: Store<Utilities.Unit, ProductRequestAction>
    
    // VC-specific UI state
    
    private var presentedDialog: DialogScreen? = .none
    
    // Views
    private let accountNameViewWrapper = PsiCashAccountNameViewWrapper()
    private let balanceViewWrapper: PsiCashBalanceViewWrapper
    private let closeButton = CloseButton(frame: .zero)
    
    private var vStack: UIStackView
    
    private let tabControl = TabControlViewWrapper<PsiCashScreenTab>()
    private let signupOrLogInView = PsiCashAccountSignupOrLoginView()
    
    private let containerView: ViewBuilderContainerView<ContainerViewType>
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(
        platform: Platform,
        locale: Locale,
        store: Store<ReaderState, ViewControllerAction>,
        iapStore: Store<Utilities.Unit, IAPAction>,
        productRequestStore: Store<Utilities.Unit, ProductRequestAction>,
        appStoreReceiptStore: Store<Utilities.Unit, ReceiptStateAction>,
        tunnelConnectedSignal: SignalProducer<TunnelConnectedStatus, Never>,
        dateCompare: DateCompare,
        feedbackLogger: FeedbackLogger,
        tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
        objCBridgeDelegate: ObjCBridgeDelegate,
        onDidLoad: (() -> Void)?,
        onDismissed: (() -> Void)?
    ) {
        self.platform = platform
        self.locale = locale
        self.feedbackLogger = feedbackLogger
        self.dateCompare = dateCompare
        self.tunnelConnectedSignal = tunnelConnectedSignal
        
        self.balanceViewWrapper = PsiCashBalanceViewWrapper(locale: locale)
        
        self.tunnelConnectionRefSignal = tunnelConnectionRefSignal
        
        self.vStack = UIStackView.make(
            axis: .vertical,
            distribution: .fill,
            alignment: .fill,
            spacing: Style.default.padding
        )

        self.store = store
        self.iapStore = iapStore
        self.productRequestStore = productRequestStore
        
        let messageViewWithAction = PsiCashMessageViewWithButton { [unowned objCBridgeDelegate] message in
            switch message {
            case .untunneled(_):
                // This action toggles the VPN, but it is expcected to only
                // be called when the VPN is not connected.
                objCBridgeDelegate.startStopVPN()
            }
        }
        
        self.containerView = ViewBuilderContainerView(
            EitherView(
                AddPsiCashViewType(
                    PsiCashCoinPurchaseTable(purchaseHandler: {
                        switch $0 {
                        case .product(let product):
                            store.send(.mainViewAction(.psiCashViewAction(
                                .purchaseTapped(product: product))))
                        }
                    }),
                    EitherView(Spinner(style: .whiteLarge),
                               EitherView(messageViewWithAction,
                                          EitherView(PsiCashMessageWithRetryView(),
                                                     PsiCashMessageView())))),
                SpeedBoostViewType(
                    SpeedBoostPurchaseTable(purchaseHandler: {
                        store.send(.psiCashAction(.buyPsiCashProduct(.speedBoost($0))))
                    }, getLocale: { locale }),
                    EitherView(Spinner(style: .whiteLarge),
                               EitherView(messageViewWithAction, PsiCashMessageView()))))
        )
        
        super.init(onDidLoad: onDidLoad, onDismissed: onDismissed)
        
        // Handler for "Sign Up or Log In" button.
        self.signupOrLogInView.onLogInTapped { [unowned self] in
            self.store.send(.mainViewAction(.presentPsiCashAccountExplainer))
        }

        // Updates UI by merging all necessary signals.
        self.lifetime += SignalProducer.combineLatest(
            store.$value.signalProducer,
            tunnelConnectedSignal,
            self.$lifeCycle.signalProducer
        ).map(ObservedState.init)
        .skipRepeats()
        .filter { observed in
            observed.lifeCycle.viewDidLoadOrAppeared
        }
        .startWithValues { [unowned self] observed in
            self.updateUI(observed)
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        Style.default.statusBarStyle
    }
    
    private func updateUI(_ observed: ObservedState) {
        // Even though the reactive signal has a filter on
        // `!observed.lifeCycle.viewWillOrDidDisappear`, due to async nature
        // of the signal it is ambiguous if this closure is called when
        // `self.lifeCycle.viewWillOrDidDisappear` is true.
        // Due to this race-condition, the source-of-truth (`self.lifeCycle`),
        // is checked for whether view will or did disappear.
        guard !self.lifeCycle.viewWillOrDidDisappear else {
            return
        }

        guard let psiCashViewState = observed.readerState.mainViewState.psiCashStoreViewState else {
            // View controller state has been set to nil,
            // and it will be dismissed (if not already).
            return
        }
        
        guard case let .success(psiCashLibData) = observed.readerState.psiCash.libData else {
            guard self.updateUIStateHelper(.psiCashLibFailedInit) else { fatalError() }
            return
        }
        
        // Triplet containing IAP and PsiCash purchase states.
        let purchasingNavState = (
            observed.readerState.iap.purchasing[.psiCash],
            observed.readerState.psiCash.speedBoostPurchase,
            self.presentedDialog
        )
        
        switch purchasingNavState {
        case (.none, .none, _):
            self.dismissPurchasingScreens()
            
        case (.completed(.success(_)), .none, _):
            // Last PsiCash IAP purchase finished successfully.
            self.dismissPurchasingScreens()
            
        case (.pending(_), _, .none):
            let _ = self.presentDialogScreen(.psiCashPurchaseDialog)
            
        case (.pending(_), _, .psiCashPurchaseDialog):
            break
            
        case (_, .pending(_), .none):
            let _ = self.presentDialogScreen(.speedBoostPurchaseDialog)
            
        case (_, .pending(_), .speedBoostPurchaseDialog):
            break
            
        case (_, .deferred(_), .none):
            break
            
        case (_, .error(let psiCashErrorEvent), _):
            let errorDesc = ErrorEventDescription(
                event: psiCashErrorEvent.eraseToRepr(),
                localizedUserDescription: psiCashErrorEvent.error.localizedUserDescription
            )

            self.dismissPurchasingScreens()

            switch psiCashErrorEvent.error {
            case .requestError(.errorStatus(.insufficientBalance)):
                let alertEvent = AlertEvent(
                    .psiCashAlert(
                        .insufficientBalanceErrorAlert(localizedMessage: errorDesc.localizedUserDescription)),
                        date: psiCashErrorEvent.date)

                self.store.send(.mainViewAction(.presentAlert(alertEvent)))

            default:
                let alertEvent = AlertEvent(
                    .error(
                        localizedTitle: UserStrings.Error_title(),
                        localizedMessage: errorDesc.localizedUserDescription
                    ),
                    date: psiCashErrorEvent.date
                )

                self.store.send(.mainViewAction(.presentAlert(alertEvent)))
            }

        case (.completed(.failure(let iapErrorEvent)), _, _):
            self.dismissPurchasingScreens()
            
            if let errorDesc = iapErrorEvent.localizedErrorEventDescription {

                let alertEvent = AlertEvent(
                    .error(
                        localizedTitle: UserStrings.Purchase_failed(),
                        localizedMessage: errorDesc.localizedUserDescription
                    ),
                    date: iapErrorEvent.date
                )

                self.store.send(.mainViewAction(.presentAlert(alertEvent)))
            }
            
        default:
            feedbackLogger.fatalError("""
                    Invalid purchase navigation state combination: \
                    '\(String(describing: purchasingNavState))',
                    """)
            return
        }

        // Updates active tab UI
        self.tabControl.bind(psiCashViewState.activeTab)
        
        // Updates PsiCash balance (this does not control whether the view is hidden or not)
        self.balanceViewWrapper.bind(observed.readerState.psiCashBalanceViewModel)
        
        // Sets account username if availalbe
        if let accountName = psiCashLibData.accountUsername {
            self.accountNameViewWrapper.bind(accountName)
        }
        
        switch observed.readerState.subscription.status {
        case .unknown:
            guard self.updateUIStateHelper(.unknownSubscription) else {
                fatalError()
            }
            return
            
        case .subscribed(_):
            guard self.updateUIStateHelper(.subscribed(psiCashLibData.accountType)) else {
                fatalError()
            }
            return
            
        case .notSubscribed:
        
            let handled = self.updateUIStateHelper(
                .notSubscribed(
                    observed.tunneled,
                    psiCashLibData.accountType,
                    observed.readerState.psiCash.isLoggingInOrOut
                )
            )
            
            if handled {
                return
            }
            
            // Invariants:
            // - User not subscribed
            // - Not in a tunnel transition state (connecting, disconnecting).
            // - PsiCash token state: is tracker or logged in
            // - Not pending login/logout
            guard
                (observed.tunneled == .connected || observed.tunneled == .notConnected),
                (psiCashLibData.accountType == .tracker ||
                 psiCashLibData.accountType == .account(loggedIn: true)),
                observed.readerState.psiCash.isLoggingInOrOut == .none
            else
            {
                // updateUIState(_:) is expected to handle all other cases.
                fatalError()
            }
            
            switch (observed.tunneled, psiCashViewState.activeTab) {
            case (.connecting, _), (.disconnecting, _):
                // Already handled by above call to self.updateUIState
                return
                
            case (.notConnected, .addPsiCash),
                 (.connected, .addPsiCash):
                
                if
                    case .completed(.success(let unfinishedPsiCashTx)) =
                        observed.readerState.iap.purchasing[.psiCash]
                {
                    switch observed.tunneled {
                    case .connected:
                        
                        // Set view content based on verification state of the
                        // unverified PsiCash IAP transaction.
                        switch unfinishedPsiCashTx.verificationStatus {
                        case .notRequested, .pendingResponse:
                            self.containerView.bind(
                                .left(.right(.right(.right(.right(
                                                            .pendingPsiCashVerification)))))
                            )
                            
                        case .requestError(_):
                            // Shows failed to verify purchase message with,
                            // tap to retry button.
                            self.containerView.bind(
                                .left(.right(.right(.right(.left(
                                                            .failedToVerifyPsiCashIAPPurchase(retryAction: {
                                                                self.iapStore.send(.retryUnverifiedTransaction)
                                                            })))))))
                            
                        }
                        
                    case .notConnected:
                        // If tunnel is not connected and there is a pending PsiCash IAP,
                        // then shows the "pending psicash purchase" screen.
                        self.containerView.bind(
                            .left(.right(.right(.left(.untunneled(.pendingPsiCashPurchase))))))
                        
                    case .connecting, .disconnecting:
                        fatalError()
                    }
                    
                } else {
                    
                    let allProducts = observed.readerState.allProducts()
                    
                    switch allProducts {
                    case .pending([]):
                        // Product list is being retrieved from the
                        // App Store for the first time.
                        // A spinner is shown.
                        self.containerView.bind(.left(.right(.left(true))))
                    case .pending(let lastSuccess):
                        // Displays product list from previous retrieval.

                        self.containerView.bind(.left(.left(.makeViewModel(purchasables: lastSuccess, accountType: psiCashLibData.accountType))))
                        
                    case .completed(let productRequestResult):
                        // Product list retrieved from App Store.
                        switch productRequestResult {
                        case .success(let psiCashCoinProducts):
                            self.containerView.bind(.left(.left(.makeViewModel(purchasables: psiCashCoinProducts, accountType: psiCashLibData.accountType))))
                            
                        case .failure(_):
                            // Shows failed to load message with tap to retry button.
                            self.containerView.bind(
                                .left(.right(.right(.right(.left(
                                                            .failedToLoadProductList(retryAction: {
                                                                self.productRequestStore.send(.getProductList)
                                                            })))))))
                        }
                    }
                }
                
            case (.connected, .speedBoost),
                 (.notConnected, .speedBoost):
                
                let activeSpeedBoost = observed.readerState.psiCash.activeSpeedBoost(dateCompare)
                
                switch activeSpeedBoost {
                case .none:
                    // There is no active speed boost.
                    // The user might have a deferred Speed Boost purchase.
                    
                    // PsiCash deferred purchase
                    switch observed.readerState.psiCash.speedBoostPurchase {
                        
                    case .deferred(_):
                        
                        switch observed.tunneled {
                            
                        case .notConnected:
                            // Deferred purchase, while untunneled.
                            // User is asked to connect to finish their transaction.
                            self.containerView.bind(
                                .right(.right(.right(.left(
                                    .untunneled(.speedBoostPurchaseDeferred))))))
                            
                        case .connected:
                            // Transitory stage. A deferred purchase will soon be
                            // pending after the tunnel has connected.
                            break
                            
                        default:
                            fatalError()
                        }
                        
                    case .none, .error(_), .pending(_):
                        // There is no deferred PsiCash purchase.
                        // In case of a pending purchase Speed Boost purchase dialog
                        // is presented.
                        
                        let sbProducts = SpeedBoostPurchasableViewModel
                            .makeArray(psiCashLibData, self.locale)
                        
                        if let viewModel = NonEmpty(array: sbProducts) {
                            
                            // Has Speed Boost products
                            self.containerView.bind(.right(.left(viewModel)))
                            
                        } else {
                            
                            // If there is no pending PsiCash refresh state, and
                            // there are no Speed Boost products, shows error message.
                            if case .pending = observed.readerState.psiCash.pendingPsiCashRefresh {
                                // Shows spinner while PsiCash refresh state is pending.
                                self.containerView.bind(.right(.right(.left(true))))
                            } else {
                                // Error state: PsiCash (Speed Boost) purchase prices are not available.
                                // If tunneled, asks the user to connect, otherwise shows
                                // no Speed Boost product available.
                                switch observed.tunneled {
                                case .connected:
                                    // Shows message that Speed Boost purchase prices
                                    // have not been fetched.
                                    self.containerView.bind(
                                        .right(.right(.right(.right(.noSpeedBoostProducts)))))
                                    
                                case .notConnected:
                                    // Shows message that Speed Boost purchasing is unavailable
                                    // and asks the user to connect.
                                    self.containerView.bind(
                                        .right(.right(.right(.left(
                                            .untunneled(.speedBoostUnavailable(subtitle: .connectToPsiphon)))))))
                                    
                                case .connecting, .disconnecting:
                                    // Should have already been handled!
                                    fatalError("unexpected state")
                                }
                            }
                            
                        }
                    }
                    
                case .some(_):
                    // There is an active speed boost.
                    self.containerView.bind(
                        .right(.right(.right(.right(.speedBoostAlreadyActive)))))
                }
            }
        }
    }
    
    /// An incomplete representation of the UI state, used only by the `updateUIStateHelper(_:)` method.
    enum _UIState: Equatable {
        
        case psiCashLibFailedInit
        
        case unknownSubscription
        
        case subscribed(PsiCashAccountType)
        
        case notSubscribed(
            TunnelConnectedStatus,
            PsiCashAccountType,
            PsiCashState.LoginLogoutPendingValue?
        )
        
    }
    
    /// `updateUIStateHelper(_:)` updates some parts of the UI.
    /// This is used alongside the main subscription to the `ObservedState`
    /// signal in the `init` method to update the UI.
    /// - Returns: True if containerView state is handled.
    private func updateUIStateHelper(_ state: _UIState) -> Bool {
        
        switch state {
            
        case .psiCashLibFailedInit:
            self.accountNameViewWrapper.view.isHidden = true
            self.balanceViewWrapper.view.isHidden = true
            self.tabControl.view.isHidden = true
            self.signupOrLogInView.isHidden = true
            
            self.containerView.bind(
                .left(.right(.right(.right(.right(.psiCashLibFailedInit)))))
            )
            
            return true
        
        case .unknownSubscription:
            self.accountNameViewWrapper.view.isHidden = true
            self.balanceViewWrapper.view.isHidden = true
            self.tabControl.view.isHidden = true
            self.signupOrLogInView.isHidden = true
            
            self.containerView.bind(
                .left(.right(.right(.right(.right(.otherErrorTryAgain)))))
            )
            
            return true
            
        case .subscribed(let psiCashAccountType):
            // User is subscribed. Only shows the PsiCash balance, and the username (if logged in).
            switch psiCashAccountType {
            case .noTokens, .tracker, .account(loggedIn: false):
                self.accountNameViewWrapper.view.isHidden = true
            case .account(loggedIn: true):
                self.accountNameViewWrapper.view.isHidden = false
            }
            self.balanceViewWrapper.view.isHidden = false
            self.tabControl.view.isHidden = true
            self.signupOrLogInView.isHidden = true
                        
            self.containerView.bind(
                .left(.right(.right(.right(.right(.userSubscribed)))))
            )
            
            return true
            
        case let .notSubscribed(
            tunnelStatus, psiCashAccountType, maybePendingPsiCashLoginLogout):
            
            // Blocks UI and displays appropriate message if tunnel is connecting or disconnecting.
            switch tunnelStatus {
            case .connecting:
                self.accountNameViewWrapper.view.isHidden = true
                self.balanceViewWrapper.view.isHidden = true
                self.tabControl.view.isHidden = true
                self.signupOrLogInView.isHidden = true
                
                self.containerView.bind(
                    .left(.right(.right(.right(.right(.psiphonIsConnecting))))))
                
                return true
                
            case .disconnecting:
                
                self.accountNameViewWrapper.view.isHidden = true
                self.balanceViewWrapper.view.isHidden = true
                self.tabControl.view.isHidden = true
                self.signupOrLogInView.isHidden = true
                
                self.containerView.bind(
                    .left(.right(.right(.right(.right(.unavailableWhileDisconnecting))))))
             
                return true
                
            default:
                break
                
            }
            
            // Blocks UI and displays appropriate message if user is logging in or loggign out.
            switch maybePendingPsiCashLoginLogout {
            
            case .none:
                break
                
            case .login:
                self.accountNameViewWrapper.view.isHidden = true
                self.balanceViewWrapper.view.isHidden = true
                self.tabControl.view.isHidden = true
                self.signupOrLogInView.isHidden = false
                
                self.containerView.bind(
                    .left(.right(.right(.right(.right(.psiCashAccountsLoggingIn))))))
                
                return true
                
            case .logout:
                self.accountNameViewWrapper.view.isHidden = true
                self.balanceViewWrapper.view.isHidden = true
                self.tabControl.view.isHidden = true
                self.signupOrLogInView.isHidden = true
                
                self.containerView.bind(
                    .left(.right(.right(.right(.right(.psiCashAccountsLoggingOut))))))
                
                return true
                
            }
            
            switch psiCashAccountType {
            case .noTokens:
                self.accountNameViewWrapper.view.isHidden = true
                self.balanceViewWrapper.view.isHidden = true
                self.tabControl.view.isHidden = true
                self.signupOrLogInView.isHidden = true
                
                self.containerView.bind(
                    .left(.right(.right(.right(.right(.otherErrorTryAgain)))))
                )
                
                return true
                
            case .account(loggedIn: false):
                
                self.accountNameViewWrapper.view.isHidden = true
                self.balanceViewWrapper.view.isHidden = true
                self.tabControl.view.isHidden = true
                self.signupOrLogInView.isHidden = false
                
                self.containerView.bind(
                    .left(.right(.right(.right(.right(.signupOrLoginToPsiCash)))))
                )
                
                return true
                
            case .account(loggedIn: true):
                
                self.accountNameViewWrapper.view.isHidden = false
                self.balanceViewWrapper.view.isHidden = false
                self.tabControl.view.isHidden = false
                self.signupOrLogInView.isHidden = true
                
                return false
                
            case .tracker:
                
                self.accountNameViewWrapper.view.isHidden = true
                self.balanceViewWrapper.view.isHidden = false
                self.tabControl.view.isHidden = false
                self.signupOrLogInView.isHidden = false
                
                return false
                
            }
            
        }
        
    }
    
    // Setup and add all the views here
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setBackgroundGradient(for: view)
        
        tabControl.setTabHandler { [unowned self] tab in
            self.store.send(.mainViewAction(.psiCashViewAction(.switchTabs(tab))))
        }
        
        closeButton.setEventHandler { [unowned self] in
            self.dismiss(animated: true, completion: nil)
        }
        
        closeButton.accessibilityIdentifier = "psiCashScreenCloseButton"
        
        vStack.addArrangedSubviews(
            signupOrLogInView,
            tabControl.view,
            containerView.view
        )
        
        // Add subviews
        view.addSubviews(
            accountNameViewWrapper.view,
            balanceViewWrapper.view,
            closeButton,
            vStack
        )
        
        // Setup layout guide
        let rootViewLayoutGuide = makeSafeAreaLayoutGuide(addToView: view)
        
        let paddedLayoutGuide = UILayoutGuide()
        view.addLayoutGuide(paddedLayoutGuide)
        
        paddedLayoutGuide.activateConstraints {
            $0.constraint(
                to: rootViewLayoutGuide,
                .top(Float(Style.default.padding)),
                .bottom(),
                .centerX()
            )
            +
            $0.widthAnchor.constraint(
                toDimension: rootViewLayoutGuide.widthAnchor,
                ratio: Style.default.layoutWidthToHeightRatio,
                max: Style.default.layoutMaxWidth
            )
        }
        
        self.balanceViewWrapper.view.setContentHuggingPriority(
            higherThan: self.vStack, for: .vertical)
        
        self.signupOrLogInView.setContentHuggingPriority(
            higherThan: self.vStack, for: .vertical)
        
        self.accountNameViewWrapper.view.activateConstraints {
            $0.constraint(to: paddedLayoutGuide, .centerX(), .top(Float(Style.default.padding))) +
            [
                $0.leadingAnchor.constraint(greaterThanOrEqualTo: paddedLayoutGuide.leadingAnchor),
                $0.trailingAnchor.constraint(lessThanOrEqualTo: self.closeButton.leadingAnchor)
            ]
        }
        
        self.closeButton.activateConstraints {
            $0.constraint(to: paddedLayoutGuide, .trailing(), .top(Float(Style.default.largePadding)))
        }
                
        self.balanceViewWrapper.view.activateConstraints {
            $0.constraint(to: paddedLayoutGuide, .centerX(0, .belowRequired)) +
            [
                $0.topAnchor.constraint(
                    equalTo: self.accountNameViewWrapper.view.bottomAnchor,
                    constant: 5.0),
                $0.leadingAnchor.constraint(greaterThanOrEqualTo: paddedLayoutGuide.leadingAnchor),
                $0.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor)
            ]
        }
        
        self.vStack.activateConstraints {
            $0.constraint(to: paddedLayoutGuide, .bottom(), .leading(), .trailing()) + [
                $0.topAnchor.constraint(equalTo: self.balanceViewWrapper.view.bottomAnchor,
                                        constant: Style.default.largePadding) ]
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        productRequestStore.send(.getProductList)
    }
    
}

// Navigations
extension PsiCashStoreViewController {
    
    private func dismissPurchasingScreens() {
        switch self.presentedDialog {
        case .none:
            return
        case .psiCashPurchaseDialog, .speedBoostPurchaseDialog:
            let _ = self.presentDialogScreen(.none)
        }
    }
    
    private func presentDialogScreen(_ screen: DialogScreen?) -> Bool {
        
        // Can only navigate to a new screen from the main screen,
        // otherwise what should be presented is not well-defined.
        
        guard self.presentedDialog != screen else {
            // Already displaying `screen`.
            return true
        }
        
        if case .none = screen {
            guard let presentedViewController = self.presentedViewController else {
                // There is no presentation to dismiss.
                return true
            }
            
            UIViewController.safeDismiss(presentedViewController,
                                         animated: false,
                                         completion: nil)
            
            self.presentedDialog = .none
            return true
            
        } else {
            
            // Presenting a new screen is only well-defined current screen is the main screen.
            guard case .none = self.presentedDialog else {
                return false
            }

            let alertViewBuilder: PurchasingAlertViewBuilder
            switch screen {
            case .none:
                fatalError()
            case .psiCashPurchaseDialog:
                alertViewBuilder = PurchasingAlertViewBuilder(alert: .psiCash, locale: locale)
            case .speedBoostPurchaseDialog:
                alertViewBuilder = PurchasingAlertViewBuilder(alert: .speedBoost, locale: locale)
            }
            
            let vc = ViewBuilderViewController(
                modalPresentationStyle: .overFullScreen,
                viewBuilder: alertViewBuilder,
                onDidLoad: nil,
                onDismissed: nil
            )

            self.presentOnViewDidAppear(vc, animated: false, completion: nil)
            
            self.presentedDialog = screen
            return true
        }
    }
    
}

extension ErrorEvent where E == IAPState.IAPError {
    
    /// Returns an `ErrorEventDescription` if the error represents a user-facing error, otherwise returns `nil`.
    fileprivate var localizedErrorEventDescription: ErrorEventDescription<ErrorRepr>? {
        let optionalDescription: String?
        
        switch self.error {
        
        case let .failedToCreatePurchase(reason: reason):
            optionalDescription = reason
            
        case let .storeKitError(error: transactionError):
            
            switch transactionError {
            case .invalidTransaction:
                optionalDescription = "App Store failed to record the purchase"
                
            case let .error(skEmittedError):

                // Payment cancelled errors are ignored.
                if case let .right(skError) = skEmittedError,
                   case .paymentCancelled = skError.errorInfo.code {

                    optionalDescription = .none

                } else {

                    let desc: String
                    switch skEmittedError {
                    case .left(let error):
                        desc = error.errorInfo.localizedDescription
                    case .right(let error):
                        desc = error.errorInfo.localizedDescription
                    }

                    optionalDescription = """
                        \(UserStrings.Operation_failed_please_try_again_alert_message())
                        (\(desc))
                        """

                }
            }
        }
        
        guard let description = optionalDescription else {
            return nil
        }
        return ErrorEventDescription(event: self.eraseToRepr(),
                                     localizedUserDescription: description)
    }
    
}

fileprivate extension PsiCashCoinPurchaseTable.ViewModel {
    
    static func makeViewModel(
        purchasables: [PsiCashPurchasableViewModel], accountType: PsiCashAccountType
    ) -> Self {
        let footerText: String?
        if case .tracker = accountType {
            footerText = UserStrings.PsiCash_non_account_purchase_notice()
        } else {
           footerText = nil
        }
        return .init(purchasables: purchasables, footerText: footerText)
    }
    
}

extension PsiCashStoreViewController.ReaderState {

    /// Adds rewarded video product to list of `PsiCashPurchasableViewModel`  retrieved from AppStore.
    func allProducts() -> PendingWithLastSuccess<[PsiCashPurchasableViewModel], SystemErrorEvent<Int>> {
        
        return appStorePsiCashProducts.map(
            pending: { $0.compactMap { $0.viewModel } },
            completed: { $0.map { $0.compactMap { $0.viewModel } } }
        )

    }

}

extension SpeedBoostPurchasableViewModel {
    
    // Convenience function to create view model for the Speed Boost products.
    static func makeArray(
        _ psiCashLibData: PsiCashLibData,
        _ locale: Locale
    ) -> [Self] {
        
        let speedBoostPurchasables = psiCashLibData.purchasePrices.compactMap {
            $0.successToOptional()?.speedBoost
        }
        .filter { $0.product.distinguisher.availableForSale }
        .map { purchasable -> SpeedBoostPurchasableViewModel in
            
            let productTitle = purchasable.product.localizedString
                .uppercased(with: locale)
            
            return SpeedBoostPurchasableViewModel(
                purchasable: purchasable,
                localizedProductTitle: productTitle
            )
            
        }
        .sorted() // Sorts by Comparable impl of SpeedBoostPurchasableViewModel.
        
        return speedBoostPurchasables
        
    }
    
}
