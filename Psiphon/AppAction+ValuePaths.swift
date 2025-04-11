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

extension AppAction {
    
    var appDelegateAction: AppDelegateAction? {
        get {
            guard case let .appDelegateAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .appDelegateAction = self, let newValue = newValue else { return }
            self = .appDelegateAction(newValue)
        }
    }
    
    var psiCash: PsiCashAction? {
        get {
            guard case let .psiCash(value) = self else { return nil }
            return value
        }
        set {
            guard case .psiCash = self, let newValue = newValue else { return }
            self = .psiCash(newValue)
        }
    }
    
    var landingPage: LandingPageAction? {
        get {
            guard case let .landingPage(value) = self else { return nil }
            return value
        }
        set {
            guard case .landingPage = self, let newValue = newValue else { return }
            self = .landingPage(newValue)
        }
    }
    
    var inAppPurchase: IAPAction? {
        get {
            guard case let .iap(value) = self else { return nil }
            return value
        }
        set {
            guard case .iap = self, let newValue = newValue else { return }
            self = .iap(newValue)
        }
    }
    
    var appReceipt: ReceiptStateAction? {
        get {
            guard case let .appReceipt(value) = self else { return nil }
            return value
        }
        set {
            guard case .appReceipt = self, let newValue = newValue else { return }
            self = .appReceipt(newValue)
        }
    }
    
    var subscription: SubscriptionAction? {
        get {
            guard case let .subscription(value) = self else { return nil }
            return value
        }
        set {
            guard case .subscription = self, let newValue = newValue else { return }
            self = .subscription(newValue)
        }
    }
    
    var subscriptionAuthStateAction: SubscriptionAuthStateAction? {
        get {
            guard case let .subscriptionAuthStateAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .subscriptionAuthStateAction = self, let newValue = newValue else { return }
            self = .subscriptionAuthStateAction(newValue)
        }
    }
    
    var productRequest: ProductRequestAction? {
        get {
            guard case let .productRequest(value) = self else { return nil }
            return value
        }
        set {
            guard case .productRequest = self, let newValue = newValue else { return }
            self = .productRequest(newValue)
        }
    }
    
    var vpnStateAction: VPNStateAction<PsiphonTPM>? {
        get {
            guard case let .vpnStateAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .vpnStateAction = self, let newValue = newValue else { return }
            self = .vpnStateAction(newValue)
        }
    }
    
    var feedbackAction: FeedbackAction? {
        get {
            guard case let .feedbackAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .feedbackAction = self, let newValue = newValue else { return }
            self = .feedbackAction(newValue)
        }
    }
    
    var mainViewAction: MainViewAction? {
        get {
            guard case let .mainViewAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .mainViewAction = self, let newValue = newValue else { return }
            self = .mainViewAction(newValue)
        }
    }
    
    var serverRegionAction: ServerRegionAction? {
        get {
            guard case let .serverRegionAction(value) = self else { return nil }
            return value
        }
        set {
            guard case .serverRegionAction = self, let newValue = newValue else { return }
            self = .serverRegionAction(newValue)
        }
    }
    
}
