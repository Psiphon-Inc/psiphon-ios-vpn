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
import Chalk

public struct PrettyPrinter {

    let indetation: String = " "
    let tabWidth: Int = 2
    let oneLineCharLimit: Int = 80

    let color = Color.white
    let typeColor = Color.extended(36)     // green
    let enumColor = Color.extended(127)    // purple
    let numberColor = Color.extended(123)  // cyan
    let stringColor = Color.extended(191)  // yellow
    let valueColor = Color.extended(196)   // red
    
    let formatDate: (Date) -> String

    public init(timeZone: String?) {
        if let timeZone = timeZone {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]
            dateFormatter.timeZone = TimeZone(identifier: timeZone)
            formatDate = { dateFormatter.string(from: $0) }
        } else {
            formatDate = { $0.description }
        }
    }

    private func spaces(indent: Int) -> String {

        String(repeating: " ", count: indent * tabWidth)

    }

    // Not perfect, but it works.
    public func prettyPrint(_ value: AppStateValue, _ level: Int = 0, highlight: Bool) -> [[String]] {

        switch value {

        case .enumValue(let text):
            
            return [[ "\(text, color: enumColor, apply: highlight)" ]]
            
        case .string(let text):
            let quoted = "\"\(text)\""  // Wraps string value in quotes
            return [[ "\(quoted, color: stringColor, apply: highlight)" ]]
            
        case .custom(let text):
            return [[ "\(text, color: stringColor, apply: highlight)" ]]
            
        case .number(let text):
            return [[ "\(text, color: numberColor, apply: highlight)" ]]

        case .date(let date):
            return [[ "\(self.formatDate(date), color: valueColor, apply: highlight)" ]]

        case let .type(typeName, typeValue):

            let fields = prettyPrint(typeValue, level + 1, highlight: highlight)

            if fields.count == 0 {

                return [[typeName]]

            } else {

                let oneLineCharCount = fields.map { $0.map { $0.count }.reduce(0, +) }.reduce(0, +)

                if oneLineCharCount < oneLineCharLimit {

                    let oneLiner = fields.flatten().joined()
                    return [[ "\(typeName, color: typeColor, apply: highlight)(\(oneLiner))" ]]

                } else {

                    return [[ "\(typeName, color: typeColor, apply: highlight)(" ] + fields.indent(spaces(indent: 1)).flatten() + [ ")" ]]

                }
            }

        case let .tuple(tuple):

            if tuple.isEmpty {

                return [[ "()" ]]

            } else {

                let fields = tuple.flatMap {
                    prettyPrint($0, level + 1, highlight: highlight)
                        .indent(spaces(indent: level + 1))
                }

                return [[ "(" ] + fields.flatten() + [ ")" ]]

            }

        case .array(let array):

            if array.isEmpty {

                return [[ "\("[]", color: valueColor, apply: highlight)" ]]

            } else {

                return [[ "[" ] +
                            array.map {
                                prettyPrint($0, level + 1, highlight: highlight).flatten()
                            }.indent(spaces(indent: 1)).commaSeparated().flatten() +
                            [ "]" ]]

            }

        case .object(let fields):
            let objectFields = fields.flatMap { (maybeName, value) -> [[String]] in

                var prettyPrintedValue = prettyPrint(value, level, highlight: highlight)

                if let name = maybeName {
                    if let first = prettyPrintedValue.first {
                        prettyPrintedValue.removeFirst()
                        let rest = prettyPrintedValue.flatten()
                        return [ ["\(name): \(first.first!)"] + Array(first.dropFirst()) + rest ]
                    } else {
                        return [["()"]]
                    }
                } else {
                    return prettyPrintedValue
                }

            }

            return objectFields.commaSeparated()

        case .dictionary(let dict):

            if dict.isEmpty {

                return [[ "\("[:]", color: valueColor, apply: highlight)" ]]

            } else {

                let fields =  dict.flatMap { (name, value) -> [[String]]  in

                    let prettyPrintedName = prettyPrint(name, level + 1, highlight: highlight).flatten().joined()
                    let prettyPrintedValue = prettyPrint(value, level + 1, highlight: highlight)

                    let first = prettyPrintedValue.flatten().joined(separator: "\n")
                    let rest = Array(prettyPrintedValue.dropFirst())

                    return [[ "\(prettyPrintedName): \(first)" ] + rest.flatten() ]

                }.commaSeparated()

                return [ [ "[" ] + fields.indent(spaces(indent: 1)).flatten() + [ "]" ] ]

            }
            
        case .jsonObject(let fields):
            if fields.isEmpty {

                return [[ "\("{}", color: valueColor, apply: highlight)" ]]

            } else {

                let fields =  fields.flatMap { (name, value) -> [[String]]  in

                    let prettyPrintedName = prettyPrint(.string(name), level + 1, highlight: highlight).flatten().joined()
                    let prettyPrintedValue = prettyPrint(value, level + 1, highlight: highlight)

                    let first = prettyPrintedValue.flatten().joined(separator: "\n")
                    let rest = Array(prettyPrintedValue.dropFirst())

                    return [[ "\(prettyPrintedName): \(first)" ] + rest.flatten() ]

                }.commaSeparated()

                return [ [ "{" ] + fields.indent(spaces(indent: 1)).flatten() + [ "}" ] ]

            }

        }

    }

}
