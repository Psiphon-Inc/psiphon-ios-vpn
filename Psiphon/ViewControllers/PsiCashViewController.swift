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

final class PsiCashViewController: ReactiveViewController {
    
    typealias AddPsiCashViewType =
        EitherView<PsiCashCoinPurchaseTable,
                   EitherView<Spinner,
                              EitherView<PsiCashMessageViewUntunneled,
                                         EitherView<PsiCashMessageWithRetryView,
                                                    PsiCashMessageView>>>>
    
    typealias SpeedBoostViewType = EitherView<SpeedBoostPurchaseTable,
                                              EitherView<Spinner,
                                                         EitherView<PsiCashMessageViewUntunneled,
                                                                    PsiCashMessageView>>>
    
    typealias ContainerViewType = EitherView<AddPsiCashViewType, SpeedBoostViewType>

    struct ReaderState: Equatable {
        let mainViewState: MainViewState
        let psiCashBalanceViewModel: PsiCashBalanceViewModel
        let psiCash: PsiCashState
        let iap: IAPState
        let subscription: SubscriptionState
        let adState: AdState
        let appStorePsiCashProducts:
            PendingWithLastSuccess<[ParsedPsiCashAppStorePurchasable], SystemErrorEvent<Int>>
        let isRefreshingAppStoreReceipt: Bool
    }

    enum ViewControllerAction: Equatable {
        case psiCashAction(PsiCashAction)
        case mainViewAction(MainViewAction)
    }
    
    struct ObservedState: Equatable {
        let readerState: ReaderState
        let tunneled: TunnelConnectedStatus
        let lifeCycle: ViewControllerLifeCycle
    }
    
    enum Screen: Equatable {
        case mainScreen
        case psiCashPurchaseDialog
        case speedBoostPurchaseDialog
    }

    private let platform: Platform
    private let locale: Locale
    private let feedbackLogger: FeedbackLogger
    private let tunnelConnectedSignal: SignalProducer<TunnelConnectedStatus, Never>
    
    private let tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>
    
    private let (lifetime, token) = Lifetime.make()
    private let store: Store<ReaderState, ViewControllerAction>
    
    private let productRequestStore: Store<Utilities.Unit, ProductRequestAction>
    
    // VC-specific UI state
    
    private var navigation: Screen = .mainScreen
    
    // Views
    private let accountViewWrapper = PsiCashAccountNameViewWrapper()
    private let balanceViewWrapper = PsiCashBalanceViewWrapper()
    private let closeButton = CloseButton(frame: .zero)
    
    private var vStack: UIStackView
    
    private let tabControl = TabControlViewWrapper<PsiCashScreenTab>()
    private let signupOrLogInView = PsiCashAccountSignupOrLoginView()
    
    private let containerView: ViewBuilderContainerView<ContainerViewType>
    
    init(
        platform: Platform,
        locale: Locale,
        store: Store<ReaderState, ViewControllerAction>,
        adStore: Store<Utilities.Unit, AdAction>,
        iapStore: Store<Utilities.Unit, IAPAction>,
        productRequestStore: Store<Utilities.Unit, ProductRequestAction>,
        appStoreReceiptStore: Store<Utilities.Unit, ReceiptStateAction>,
        tunnelConnectedSignal: SignalProducer<TunnelConnectedStatus, Never>,
        dateCompare: DateCompare,
        feedbackLogger: FeedbackLogger,
        tunnelConnectionRefSignal: SignalProducer<TunnelConnection?, Never>,
        onDismissed: @escaping () -> Void
    ) {
        self.platform = platform
        self.locale = locale
        self.feedbackLogger = feedbackLogger
        self.tunnelConnectedSignal = tunnelConnectedSignal
        
        self.tunnelConnectionRefSignal = tunnelConnectionRefSignal
        
        self.vStack = UIStackView.make(
            axis: .vertical,
            distribution: .fill,
            alignment: .fill,
            spacing: Style.default.padding
        )

        self.store = store
        self.productRequestStore = productRequestStore
        
        self.containerView = ViewBuilderContainerView(
            EitherView(
                AddPsiCashViewType(
                    PsiCashCoinPurchaseTable(purchaseHandler: {
                        switch $0 {
                        case .rewardedVideoAd:
                            adStore.send(.loadRewardedVideo(presentAfterLoad: true))
                        case .product(let product):
                            store.send(.mainViewAction(.psiCashViewAction(
                                                        .purchaseTapped(product: product))))
                        }
                    }),
                    EitherView(Spinner(style: .whiteLarge),
                               EitherView(PsiCashMessageViewUntunneled(action: {
                            store.send(.psiCashAction(.connectToPsiphonTapped))
                          }), EitherView(PsiCashMessageWithRetryView(),
                                    PsiCashMessageView())))),
                SpeedBoostViewType(
                    SpeedBoostPurchaseTable(purchaseHandler: {
                        store.send(.psiCashAction(.buyPsiCashProduct(.speedBoost($0))))
                    }),
                    EitherView(Spinner(style: .whiteLarge),
                               EitherView(PsiCashMessageViewUntunneled(action: {
                            store.send(.psiCashAction(.connectToPsiphonTapped))
                          }), PsiCashMessageView()))))
        )
                
        super.init(onDismissed: onDismissed)
        
        // Handler for "Sign Up or Log In" button.
        self.signupOrLogInView.onLogInTapped { [unowned self] in
            self.store.send(.mainViewAction(.psiCashViewAction(.presentPsiCashAccountScreen())))
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
            
            // Even though the reactive signal has a filter on
            // `!observed.lifeCycle.viewWillOrDidDisappear`, due to async nature
            // of the signal it is ambiguous if this closure is called when
            // `self.lifeCycle.viewWillOrDidDisappear` is true.
            // Due to this race-condition, the source-of-truth (`self.lifeCycle`),
            // is checked for whether view will or did disappear.
            guard !self.lifeCycle.viewWillOrDidDisappear else {
                return
            }

            guard let psiCashViewState = observed.readerState.mainViewState.psiCashViewState else {
                // View controller state has been set to nil,
                // and it will be dismissed (if not already).
                return
            }
            
            guard let psiCashLibData = observed.readerState.psiCash.libData else {
                fatalError("PsiCash lib not loaded")
            }
            
            // Presents alert if rewarded video load failed.
            if case .loadFailed(let rewardedVideoLoadFailure) =
                observed.readerState.adState.rewardedVideoAdControllerStatus {
                
                let alertEvent = AlertEvent(
                    .error(localizedMessage: UserStrings.Rewarded_video_load_failed()),
                    date: rewardedVideoLoadFailure.date
                )
                
                self.store.send(.mainViewAction(.presentAlert(alertEvent)))

            }
            
            let psiCashIAPPurchase = observed.readerState.iap.purchasing[.psiCash] ?? nil
            let purchasingNavState = (psiCashIAPPurchase?.purchasingState,
                                      observed.readerState.psiCash.purchasing,
                                      self.navigation)
            
            switch purchasingNavState {
            case (.none, .none, _):
                self.dismissPurchasingScreens()
                
            case (.pending(_), _, .mainScreen):
                let _ = self.display(screen: .psiCashPurchaseDialog)
                
            case (.pending(_), _, .psiCashPurchaseDialog):
                break
                
            case (_, .speedBoost(_), .mainScreen):
                let _ = self.display(screen: .speedBoostPurchaseDialog)
                
            case (_, .speedBoost(_), .speedBoostPurchaseDialog):
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
                        .error(localizedMessage: errorDesc.localizedUserDescription),
                        date: psiCashErrorEvent.date
                    )

                    self.store.send(.mainViewAction(.presentAlert(alertEvent)))
                }

            case (.completed(let iapErrorEvent), _, _):
                self.dismissPurchasingScreens()
                if let errorDesc = iapErrorEvent.localizedErrorEventDescription {

                    let alertEvent = AlertEvent(
                        .error(localizedMessage: errorDesc.localizedUserDescription),
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
            
            switch observed.readerState.subscription.status {
            case .unknown:
                // There is not PsiCash state or subscription state is unknown.
                self.accountViewWrapper.view.isHidden = true
                self.balanceViewWrapper.view.isHidden = true
                self.tabControl.view.isHidden = true
                self.signupOrLogInView.isHidden = true
                self.containerView.bind(
                    .left(.right(.right(.right(.right(.otherErrorTryAgain)))))
                )
                return
                
            case .subscribed(_):
                // User is subscribed. Only shows the PsiCash balance.
                self.accountViewWrapper.view.isHidden = true
                self.balanceViewWrapper.view.isHidden = false
                self.tabControl.view.isHidden = true
                self.signupOrLogInView.isHidden = true
                self.balanceViewWrapper.bind(observed.readerState.psiCashBalanceViewModel)
                self.containerView.bind(
                    .left(.right(.right(.right(.right(.userSubscribed)))))
                )
                return
                
            case .notSubscribed:

                // PsiCash account type
                switch psiCashLibData.accountType {
                case .noTokens:
                    self.accountViewWrapper.view.isHidden = true
                    self.balanceViewWrapper.view.isHidden = true
                    self.tabControl.view.isHidden = true
                    self.signupOrLogInView.isHidden = true
                    self.containerView.bind(
                        .left(.right(.right(.right(.right(.otherErrorTryAgain)))))
                    )
                    return
                    
                case .tracker:
                    self.accountViewWrapper.view.isHidden = true

                case .account(loggedIn: false):
                    // User was previously logged in, and now they are logged out.

                    self.accountViewWrapper.view.isHidden = true
                    self.balanceViewWrapper.view.isHidden = true
                    self.tabControl.view.isHidden = true

                    self.signupOrLogInView.isHidden = false

                    self.containerView.bind(
                        .left(.right(.right(.right(.right(.signupOrLoginToPsiCash)))))
                    )
                    return

                case .account(loggedIn: true):
                    
                    // Updates account name.
                    
                    self.accountViewWrapper.view.isHidden = false
                    
                    guard let accountName = observed.readerState.psiCash.libData?.accountUsername else {
                        fatalError()
                    }
                    
                    self.accountViewWrapper.bind(accountName)
                    
                }


                self.balanceViewWrapper.view.isHidden = false
                self.tabControl.view.isHidden = false
                self.balanceViewWrapper.bind(observed.readerState.psiCashBalanceViewModel)

                // Sets the visibility of tabControl and logInView
                switch observed.tunneled {
                case .connecting, .disconnecting:
                    self.tabControl.view.isHidden = true
                    self.signupOrLogInView.isHidden = true
                    
                case .connected, .notConnected:
                    self.tabControl.view.isHidden = false
                    
                    if case .tracker = psiCashLibData.accountType {
                        // LogIn button is displayed to encourage the user to login.
                        self.signupOrLogInView.isHidden = false
                    } else {
                        self.signupOrLogInView.isHidden = true
                    }
                }
                
                switch (observed.tunneled, psiCashViewState.activeTab) {
                case (.connecting, _):
                    self.containerView.bind(
                        .left(.right(.right(.right(.right(.unavailableWhileConnecting))))))
                    
                case (.disconnecting, _):
                    self.containerView.bind(
                        .left(.right(.right(.right(.right(.unavailableWhileDisconnecting))))))
                    
                case (.notConnected, .addPsiCash),
                     (.connected, .addPsiCash):
                    
                    if let unverifiedPsiCashTx = observed.readerState.iap.unfinishedPsiCashTx {
                        switch observed.tunneled {
                        case .connected:
                            
                            // Set view content based on verification state of the
                            // unverified PsiCash IAP transaction.
                            switch unverifiedPsiCashTx.verification {
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
                                                                    iapStore.send(.checkUnverifiedTransaction)
                                                                })))))))
                                
                            case .purchaseNotRecordedByAppStore:
                                self.containerView.bind(.left(.right(.right(.right(.left(.transactionNotRecordedByAppStore(
                                    isRefreshingReceipt: observed.readerState.isRefreshingAppStoreReceipt,
                                    retryAction: {
                                        appStoreReceiptStore.send(
                                            .remoteReceiptRefresh(optionalPromise: nil))
                                    }
                                )))))))
                            }
                            
                        case .notConnected:
                            // If tunnel is not connected and there is a pending PsiCash IAP,
                            // then shows the "pending psicash purchase" screen.
                            self.containerView.bind(
                                .left(.right(.right(.left(.pendingPsiCashPurchase))))
                            )
                        case .connecting, .disconnecting:
                            fatalError()
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
                            fatalError()
                        }
                        
                        let allProducts = observed.readerState.allProducts(
                            platform: platform,
                            rewardedVideoClearedForSale: rewardedVideoClearedForSale,
                            rewardedVideoSubtitle: rewardedVideoSubtitle
                        )
                        
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
                                                                    productRequestStore.send(.getProductList)
                                                                })))))))
                            }
                        }
                    }
                    
                case (.notConnected, .speedBoost):
                    
                    let activeSpeedBoost = observed.readerState.psiCash.activeSpeedBoost(dateCompare)
                    
                    switch activeSpeedBoost {
                    case .none:
                        // There is no active speed boost.
                        let connectToPsiphonMessage =
                            PsiCashMessageViewUntunneled.Message
                            .speedBoostUnavailable(subtitle: .connectToPsiphon)
                        
                        self.containerView.bind(
                            .right(.right(.right(.left(connectToPsiphonMessage)))))
                        
                    case .some(_):
                        // There is an active speed boost.
                        self.containerView.bind(
                            .right(.right(.right(.left(.speedBoostAlreadyActive)))))
                    }
                    
                case (.connected, .speedBoost):
                    
                    let activeSpeedBoost = observed.readerState.psiCash.activeSpeedBoost(dateCompare)
                    
                    switch activeSpeedBoost {
                    case .none:
                        // There is no active speed boost.
                        let speedBoostPurchasables =
                            psiCashLibData.purchasePrices.compactMap {
                                $0.successToOptional()?.speedBoost
                            }
                            .map { purchasable -> SpeedBoostPurchasableViewModel in
                                
                                let productTitle = purchasable.product.localizedString
                                    .uppercased(with: self.locale)
                                
                                return SpeedBoostPurchasableViewModel(
                                    purchasable: purchasable,
                                    localizedProductTitle: productTitle
                                )
                            }
                            .sorted() // Sorts by Comparable impl of SpeedBoostPurchasableViewModel.
                        
                        let viewModel = NonEmpty(array: speedBoostPurchasables)
                        
                        if let viewModel = viewModel {
                            self.containerView.bind(.right(.left(viewModel)))
                        } else {
                            let tryAgainLater = PsiCashMessageViewUntunneled.Message
                                .speedBoostUnavailable(subtitle: .tryAgainLater)
                            self.containerView.bind(
                                .right(.right(.right(.left(tryAgainLater)))))
                        }
                        
                    case .some(_):
                        // There is an active speed boost.
                        self.containerView.bind(
                            .right(.right(.right(.right(.speedBoostAlreadyActive)))))
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
        super.viewDidLoad()
        
        setBackgroundGradient(for: view)
        
        tabControl.setTabHandler { [unowned self] tab in
            self.store.send(.mainViewAction(.psiCashViewAction(.switchTabs(tab))))
        }
        
        closeButton.setEventHandler { [unowned self] in
            self.dismiss(animated: true, completion: nil)
        }
        
        vStack.addArrangedSubviews(
            signupOrLogInView,
            tabControl.view,
            containerView.view
        )
        
        // Add subviews
        view.addSubviews(
            accountViewWrapper.view,
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
                .top(),
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
        
        self.closeButton.activateConstraints {
            $0.constraint(to: paddedLayoutGuide, .trailing(), .top(45))
        }
        
        self.accountViewWrapper.view.activateConstraints {
            $0.constraint(to: paddedLayoutGuide, .centerX()) + [
                $0.bottomAnchor.constraint(
                    equalTo: self.balanceViewWrapper.view.topAnchor,
                    constant: -Style.default.padding)
            ]
        }
        
        self.balanceViewWrapper.view.activateConstraints {
            $0.constraint(to: paddedLayoutGuide, .centerX(0, .belowRequired)) +
                $0.constraint(to: self.closeButton, .centerY()) + [
                    $0.trailingAnchor.constraint(lessThanOrEqualTo: self.closeButton.leadingAnchor,
                                                 constant: -5.0)
                ]
        }
        
        self.vStack.activateConstraints {
            $0.constraint(to: paddedLayoutGuide, .bottom(), .leading(), .trailing()) + [
                $0.topAnchor.constraint(equalTo: self.closeButton.bottomAnchor,
                                        constant: Style.default.padding) ]
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        productRequestStore.send(.getProductList)
    }
    
}

// Navigations
extension PsiCashViewController {
    
    private func dismissPurchasingScreens() {
        switch self.navigation {
        case .mainScreen:
            return
        case .psiCashPurchaseDialog, .speedBoostPurchaseDialog:
            let _ = self.display(screen: .mainScreen)
        }
    }
    
    private func display(screen: Screen) -> Bool {
        
        // Can only navigate to a new screen from the main screen,
        // otherwise what should be presented is not well-defined.
        
        guard self.navigation != screen else {
            // Already displaying `screen`.
            return true
        }
        
        if case .mainScreen = screen {
            guard let presentedViewController = self.presentedViewController else {
                // There is no presentation to dismiss.
                return true
            }
            
            UIViewController.safeDismiss(presentedViewController,
                                         animated: false,
                                         completion: nil)
            
            self.navigation = .mainScreen
            return true
            
        } else {
            
            // Presenting a new screen is only well-defined current screen is the main screen.
            guard case .mainScreen = self.navigation else {
                return false
            }

            let alertViewBuilder: PurchasingAlertViewBuilder
            switch screen {
            case .mainScreen:
                fatalError()
            case .psiCashPurchaseDialog:
                alertViewBuilder = PurchasingAlertViewBuilder(alert: .psiCash)
            case .speedBoostPurchaseDialog:
                alertViewBuilder = PurchasingAlertViewBuilder(alert: .speedBoost)
            }
            
            let vc = ViewBuilderViewController(
                viewBuilder: alertViewBuilder,
                modalPresentationStyle: .overFullScreen,
                onDismissed: {
                    // No-op.
                }
            )

            self.presentOnViewDidAppear(vc, animated: false, completion: nil)
            
            self.navigation = screen
            return true
        }
    }
    
}

extension ErrorEvent where E == IAPError {
    
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
                        \(UserStrings.Purchase_failed())
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

extension PsiCashViewController.ReaderState {

    /// Adds rewarded video product to list of `PsiCashPurchasableViewModel`  retrieved from AppStore.
    func allProducts(
        platform: Platform,
        rewardedVideoClearedForSale: Bool,
        rewardedVideoSubtitle: String
    ) -> PendingWithLastSuccess<[PsiCashPurchasableViewModel], SystemErrorEvent<Int>> {

        switch platform.current {

        case .iOSAppOnMac:

            return appStorePsiCashProducts.map(
                pending: { $0.compactMap { $0.viewModel } },
                completed: { $0.map { $0.compactMap { $0.viewModel } } }
            )

        case .iOS:

            // Adds rewarded video ad as the first product if running device is iOS.
            return appStorePsiCashProducts.map(pending: { lastParsedList -> [PsiCashPurchasableViewModel] in

                let viewModels = lastParsedList.compactMap { parsed -> PsiCashPurchasableViewModel? in
                    parsed.viewModel
                }

                switch viewModels {
                case []: return []
                default: return [
                    .rewardedVideoProduct(
                        clearedForSale: rewardedVideoClearedForSale,
                        subtitle: rewardedVideoSubtitle,
                        adState: self.adState
                    )
                ] + viewModels
                }

            }, completed: { result in
                result.map { parsedList -> [PsiCashPurchasableViewModel] in

                    return [
                        .rewardedVideoProduct(
                            clearedForSale: rewardedVideoClearedForSale,
                            subtitle: rewardedVideoSubtitle,
                            adState: self.adState
                        )
                    ] + parsedList.compactMap { parsed -> PsiCashPurchasableViewModel? in
                        parsed.viewModel
                    }
                }
            })

        }

    }

}
