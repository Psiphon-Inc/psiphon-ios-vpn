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

protocol FeedbackDescription {}

protocol CustomStringFeedbackDescription: FeedbackDescription, CustomStringConvertible {}

/// `NSObject` classes should not adopt this protocol, since the default  `NSObject.description` function
/// will be called instead of the default description value provided by this protocol.
protocol CustomFieldFeedbackDescription: FeedbackDescription, CustomStringConvertible {
    var feedbackFields: [String: CustomStringConvertible] { get }
}

extension CustomFieldFeedbackDescription {
    /// Default description for `CustomFeedbackDescription`.
    ///
    /// For example, given the following struct
    /// ```
    /// struct SomeValue: CustomFeedbackDescription {
    ///     let string: String
    ///     let float: Float
    ///
    ///     var feedbackFields: [String: CustomStringConvertible] {
    ///         ["float": float]
    ///     }
    /// }
    /// ```
    /// The following  value would have the following description:
    /// ```
    /// let value = SomeValue(string: "string", float: 3.14)
    /// value.description == "SomeValue([\"float\": 3.14])"
    /// ```
    public var description: String {
        feedbackFieldsDescription
    }
    
    /// For `NSObject` classes, default `description` field of `CustomFieldFeedbackDescription` will not be called.
    /// Classes that want to conform to this protocol should also override `NSObject` `description` property,
    /// and only call this function.
    public func objcClassDescription() -> String {
        feedbackFieldsDescription
    }
    
    private var feedbackFieldsDescription: String {
        "\(String(describing: Self.self))(\(String(describing: feedbackFields)))"
    }
}
