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

extension NonEmptySeq : FeedbackDescription {}

extension NonEmptySeq : CustomStringConvertible where T: CustomStringConvertible {}

extension NonEmptySeq : CustomFieldFeedbackDescription where T: CustomStringConvertible {
    public var feedbackFields: [String : CustomStringConvertible] {
        var fields : [String : CustomStringConvertible] = [:]
        switch self {
        case .elem(let x):
            fields["elem"] = x
        case .cons(let x, let xs):
            fields["cons"] = ["x": x, "xs": xs.feedbackFields]
        }
        return fields
    }
}
