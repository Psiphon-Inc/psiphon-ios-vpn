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
import PsiApi
import AppStoreIAP
import PsiCashClient
import Utilities

enum PsiCashViewAction: Equatable {

    case switchTabs(PsiCashScreenTab)
    
    /// Initiates process of purchasing `product`.
    case purchaseTapped(product: AppStoreProduct)
    
    /// Cancels purchase confirmation (if any).
    case purchaseAccountConfirmationDismissed
    
    case signupOrLoginTapped

    case _signupOrLoginTapped

    case dismissedPsiCashAccountScreen
    
    case continuePurchaseWithoutAccountTapped
    
    case psiCashAccountDidChange
}

@objc enum PsiCashScreenTab: Int, TabControlViewTabType {
    case addPsiCash
    case speedBoost

    var localizedUserDescription: String {
        switch self {
        case .addPsiCash: return UserStrings.Add_psiCash()
        case .speedBoost: return UserStrings.Speed_boost()
        }
    }
}

struct PsiCashViewState: Equatable {

    /// Represents purchasing states, before actual purchase request is made.
    enum PurchaseRequestStateValues: Equatable {
        /// There are no purchase requests.
        case none
        /// Purchase request is pending user confirming whether they would like
        /// to make the purchase with, or without a PsiCash account.
        case confirmAccountLogin(AppStoreProduct)
    }

    var psiCashIAPPurchaseRequestState: PurchaseRequestStateValues

    var activeTab: PsiCashScreenTab

    /// Whether PsiCashAccountViewController should be displayed or not.
    var isPsiCashAccountScreenShown: Bool
}

struct PsiCashViewReducerState: Equatable {
    var viewState: PsiCashViewState
    let psiCashAccountType: PsiCashAccountType
}

struct PsiCashViewEnvironment {
    let feedbackLogger: FeedbackLogger
    let iapStore: (IAPAction) -> Effect<Never>

    let getTopPresentedViewController: () -> UIViewController

    /// Makes `PsiCashAccountViewController` as root of UINavigationController.
    let makePsiCashAccountViewController: () -> UIViewController
}

let psiCashViewReducer = Reducer<PsiCashViewReducerState,
                                 PsiCashViewAction,
                                 PsiCashViewEnvironment> {
    state, action, environment in
    
    switch action {
    case .switchTabs(let newTab):
        // Mutates `activeTab` only if the value has changed.
        guard state.viewState.activeTab != newTab else {
            return []
        }
        state.viewState.activeTab = newTab
        return []

    case .purchaseTapped(product: let product):

        // Checks if there is already a purchase in progress.
        guard case .none = state.viewState.psiCashIAPPurchaseRequestState else {
            return []
        }

        guard case .psiCash = product.type else {
            return []
        }
        
        // If not logged into a PsiCash account, the user is first asked
        // to confirm whether they would like to make an account,
        // or continue the purchase without an account.
        switch state.psiCashAccountType {
        case .none:
            return [
                environment.feedbackLogger.log(
                    .error, "not allowed to make a purchase without PsiCash tokens").mapNever()
            ]

        case .account(loggedIn: true):
            state.viewState.psiCashIAPPurchaseRequestState = .none
            return [
                environment.iapStore(.purchase(product: product, resultPromise: nil)).mapNever()
            ]
            
        case .tracker,
             .account(loggedIn: false):

            state.viewState.psiCashIAPPurchaseRequestState = .confirmAccountLogin(product)

            return [
                Effect.deferred { fulfill in

                    let topVC = environment.getTopPresentedViewController()

                    let vc = ViewBuilderViewController(
                        viewBuilder: PsiCashPurchasingConfirmViewBuilder(
                            closeButtonHandler: {
                                fulfill(.purchaseAccountConfirmationDismissed)
                            },
                            signUpButtonHandler: {
                                fulfill(.signupOrLoginTapped)
                            },
                            continueWithoutAccountHandler: {
                                fulfill(.continuePurchaseWithoutAccountTapped)
                            }
                        ),
                        modalPresentationStyle: .overFullScreen,
                        onDismissed: {
                            fulfill(.purchaseAccountConfirmationDismissed)
                        }
                    )

                    vc.modalTransitionStyle = .crossDissolve

                    topVC.safePresent(vc,
                                      animated: true,
                                      viewDidAppearHandler: nil)

                }
            ]
        }
        
    case .purchaseAccountConfirmationDismissed:
        guard case .confirmAccountLogin(_) = state.viewState.psiCashIAPPurchaseRequestState else {
            return []
        }
        state.viewState.psiCashIAPPurchaseRequestState = .none

        // Dismisses presented PsiCashPurchasingConfirmViewBuilder.
        return [
            .fireAndForget {
                let topVC = environment.getTopPresentedViewController()
                let searchResult = topVC.traversePresentingStackFor(
                    type: ViewBuilderViewController<PsiCashPurchasingConfirmViewBuilder>.self)

                switch searchResult {
                case .notPresent:
                    // No-op.
                    break
                case .presentInStack(let viewController):
                    viewController.dismiss(animated: false, completion: nil)

                case .presentTopOfStack(let viewController):
                    viewController.dismiss(animated: false, completion: nil)
                }
            }
        ]
        
    case .signupOrLoginTapped:
        guard state.viewState.isPsiCashAccountScreenShown == false else {
            return []
        }

        if case .confirmAccountLogin(_) = state.viewState.psiCashIAPPurchaseRequestState {

            return [
                Effect { observer, _ in
                    let topVC = environment.getTopPresentedViewController()
                    let searchResult = topVC.traversePresentingStackFor(
                        type: ViewBuilderViewController<PsiCashPurchasingConfirmViewBuilder>.self)

                    switch searchResult {
                    case .notPresent:
                        // No-op.
                        observer.sendCompleted()
                        return

                    case .presentInStack(let viewController):
                        viewController.dismiss(animated: false, completion: {
                            observer.send(value: ._signupOrLoginTapped)
                            observer.sendCompleted()
                        })

                    case .presentTopOfStack(let viewController):
                        viewController.dismiss(animated: false, completion: {
                            observer.send(value: ._signupOrLoginTapped)
                            observer.sendCompleted()
                        })
                    }
                }
            ]
        } else {
            return [ Effect(value: ._signupOrLoginTapped) ]
        }


    case ._signupOrLoginTapped:

        guard state.viewState.isPsiCashAccountScreenShown == false else {
            environment.feedbackLogger.fatalError("unexpected state")
            return []
        }

        state.viewState.isPsiCashAccountScreenShown = true

        return [
            .fireAndForget {
                let topVC = environment.getTopPresentedViewController()
                let searchResult = topVC.traversePresentingStackFor(
                    type: PsiCashAccountViewController.self, searchChildren: true)

                switch searchResult {
                case .notPresent:
                    let accountsViewController = environment.makePsiCashAccountViewController()
                    topVC.safePresent(accountsViewController,
                                      animated: true,
                                      viewDidAppearHandler: nil)

                case .presentInStack(_),
                     .presentTopOfStack(_):
                    // No-op.
                    return
                }
            }
        ]

    case .dismissedPsiCashAccountScreen:
        guard state.viewState.isPsiCashAccountScreenShown == true else {
            return []
        }

        state.viewState.isPsiCashAccountScreenShown = false

        // If in a `.confirmAccountLogin` state after a the PsiCahAccountScreen
        // has been dismissed, and the user has logged in, then continues the purchase
        // since the PsiCash accounts screen has been dismisesd.
        // Otherwise, resets `viewState.psiCashIAPPurchasingState`.
        if case .confirmAccountLogin(let product) = state.viewState.psiCashIAPPurchaseRequestState {

            if case .account(loggedIn: true) = state.psiCashAccountType {
                state.viewState.psiCashIAPPurchaseRequestState = .none
                return [
                    environment.iapStore(.purchase(product: product, resultPromise: nil)).mapNever()
                ]
            } else {
                // User did not login. Cancels purchase request.
                state.viewState.psiCashIAPPurchaseRequestState = .none
            }
        }

        return []

    case .continuePurchaseWithoutAccountTapped:
        guard
            case .confirmAccountLogin(let product) = state.viewState.psiCashIAPPurchaseRequestState
        else {
            return []
        }
        
        state.viewState.psiCashIAPPurchaseRequestState = .none
        
        return [
            environment.iapStore(.purchase(product: product, resultPromise: nil)).mapNever(),

            // Dismisses purchase confirm screen.
            .fireAndForget {
                let topVC = environment.getTopPresentedViewController()
                let searchResult = topVC.traversePresentingStackFor(
                    type: ViewBuilderViewController<PsiCashPurchasingConfirmViewBuilder>.self)

                switch searchResult {
                case .notPresent:
                    // No-op.
                    return

                case .presentInStack(let viewController):
                    viewController.dismiss(animated: false, completion: nil)

                case .presentTopOfStack(let viewController):
                    viewController.dismiss(animated: false, completion: nil)
                }
            }
        ]

    case .psiCashAccountDidChange:
        guard case .account(loggedIn: true) = state.psiCashAccountType else {
            return []
        }
        
        state.viewState.isPsiCashAccountScreenShown = false
        
        guard
            case .confirmAccountLogin(let product) = state.viewState.psiCashIAPPurchaseRequestState
        else {
            return []
        }

        state.viewState.psiCashIAPPurchaseRequestState = .none
        
        return [
            environment.iapStore(.purchase(product: product, resultPromise: nil)).mapNever()
        ]
    }
    
}
