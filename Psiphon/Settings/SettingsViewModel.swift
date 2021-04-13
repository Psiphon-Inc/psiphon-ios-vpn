/*
 * Copyright (c) 2021, Psiphon Inc.
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

// Container for data used by `SettingsViewController`.
struct SettingsViewModel: Equatable {
    let subscriptionState: SubscriptionStatus
    let psiCashAccountType: PsiCashAccountType
    let vpnStatus: VPNStatus
    let psiCashAccountManagementURL: URL?
}

// ObjC wrapper around `SettingsViewModel`.
@objc final class ObjcSettingsViewModel: NSObject {
    
    let model: SettingsViewModel
    
    @objc var hasActiveSubscription: Bool {
        switch model.subscriptionState {
        case .subscribed(_): return true
        default: return false
        }
    }
    
    @objc var isPsiCashAccountLoggedIn: Bool {
        switch model.psiCashAccountType {
        case .account(loggedIn: true):
            return true
        case .account(loggedIn: false),
             .tracker,
             .none:
            return false
        }
    }
    
    @objc var vpnStatus: VPNStatus {
        model.vpnStatus
    }
    
    @objc var accountManagementURL: URL? {
        model.psiCashAccountManagementURL
    }
    
    init(_ model: SettingsViewModel) {
        self.model = model
    }
        
}
