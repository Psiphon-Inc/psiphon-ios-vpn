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

/// Set of PsiCash product IDs defined in App Store Connect and supproted by this verion of the app.
public enum PsiCashIAPProductIDs: String {
    
    // Raw values are defined in App Store Connect console.
    // Values here must by in sync with values defined in "psiCashProductIds.plist".
    
    case PsiCash_1_000 = "ca.psiphon.Psiphon.Consumable.PsiCash.1000"
    case PsiCash_4_000 = "ca.psiphon.Psiphon.Consumable.PsiCash.4000"
    case PsiCash_10_000 = "ca.psiphon.Psiphon.Consumable.PsiCash.10000"
    case PsiCash_30_000 = "ca.psiphon.Psiphon.Consumable.PsiCash.30000"
    case PsiCash_100_000 = "ca.psiphon.Psiphon.Consumable.PsiCash.100000"
    
    /// In-app purchase product ID as defined in the App Store Connect console.
    public var productID: ProductID { ProductID(rawValue: rawValue)! }
    
}

extension PsiCashIAPProductIDs {
    
    /// PsiCash amount in Psi units.
    public var psiCashAmount: Double {
        switch self {
        case .PsiCash_1_000: return 1000
        case .PsiCash_4_000: return 4000
        case .PsiCash_10_000: return 10_000
        case .PsiCash_30_000: return 30_000
        case .PsiCash_100_000: return 100_000
        }
    }
    
}
