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

/// Supported Speed Boost products. Raw value is the distinguisher defined by the PsiCash server.
public enum SpeedBoostDistinguisher: String, CaseIterable {
    
    // Raw values must match distinguisher values set by the PsiCash server.
    case hr1 = "1hr"
    case hr2 = "2hr"
    case hr3 = "3hr"
    case hr4 = "4hr"
    case hr5 = "5hr"
    case hr6 = "6hr"
    case hr7 = "7hr"
    case hr8 = "8hr"
    case hr9 = "9hr"
    case hr24 = "24hr"
    case day7 = "7day"
    case day31 = "31day"
    
}

extension SpeedBoostDistinguisher {
    
    /// Amount of Speed Boost hours as defined by the Speed Boost distinguisher.
    public var hours: Int {
        switch self {
        case .hr1: return 1
        case .hr2: return 2
        case .hr3: return 3
        case .hr4: return 4
        case .hr5: return 5
        case .hr6: return 6
        case .hr7: return 7
        case .hr8: return 8
        case .hr9: return 9
        case .hr24: return 24
        case .day7: return 24 * 7
        case .day31: return 24 * 31
        }
    }
    
}

extension SpeedBoostDistinguisher {
    
    /// True if Speed Boost with this distinguisher is available for sale on this client.
    public var availableForSale: Bool {
        switch self {
        case .hr1, .hr24, .day7, .day31:
            return true
                
        case .hr2, .hr3, .hr4, .hr5, .hr6, .hr7, .hr8, .hr9:
            return false
        }
    }
    
}
