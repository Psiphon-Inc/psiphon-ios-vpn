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

public struct DateCompare {
    
    public let getCurrentTime: () -> Date
    public let compareDates: (Date, Date, Calendar.Component) -> ComparisonResult
    
    public init(
        getCurrentTime: @escaping () -> Date,
        compareDates: @escaping (Date, Date, Calendar.Component) -> ComparisonResult
    ) {
        self.getCurrentTime = getCurrentTime
        self.compareDates = compareDates
    }
    
    /// Compares current date with given `date`.
    /// - Returns: .orderedSame if the two dates are equal in the given component
    /// and all larger components; otherwise, either .orderedAscending or .orderedDescending.
    public func compareToCurrentDate(
        _ date: Date, toGranularity component: Calendar.Component = .second
    ) -> ComparisonResult {
        compareDates(getCurrentTime(), date, component)
    }
    
    /// Returns true if `date` is strictly greater than current time with given `component` with default of 1 second.
    public func isGreaterThanCurrentDate(
        _ date: Date, toGranularity component: Calendar.Component = .second
    ) -> Bool {
        switch compareToCurrentDate(date, toGranularity: component) {
        case .orderedAscending:
            return true
        case .orderedSame, .orderedDescending:
            return false
        }
    }
    
}
