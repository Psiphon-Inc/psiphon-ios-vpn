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
import SwiftParsec
import Chalk

let lexer = GenericTokenParser(languageDefinition: LanguageDefinition<()>.swift)

let stringParser = GenericParser<String, (), String>.string

let noneOf = StringParser.noneOf

let symbol = lexer.symbol

// `rec` points to the returned function for implementing recursion.
public let typeParser: GenericParser<String, (), String> = .recursive { rec in

    // generic-argument → type
    // generic-argument-list → generic-argument | generic-argument , generic-argument-list
    let genericArgumentList = lexer.commaSeparated(rec)

    // generic-argument-clause → < generic-argument-list >
    let genericArgumentClause = symbol("<") *> genericArgumentList <* symbol(">")

    let optArgClause = (genericArgumentClause.map { $0.joined(separator: ", ") }).attempt
        <|>
        GenericParser(result: "")

    let unitType = symbol("()") *> GenericParser(result: "()")

    // type-identifier → type-name generic-argument-clause(opt) |
    //                   type-name generic-argument-clause(opt) . type-identifier
    let nominalType: GenericParser<String, (), String> = lexer.identifier >>- { name in

        return optArgClause >>- { argClause in

            (symbol(".") *> rec).attempt.map { subName in

                if argClause.isEmpty {
                    return "\(name).\(subName)"
                } else {
                    return "\(name)<\(argClause)>.\(subName)"
                }

            }
            <|>
            GenericParser(result: argClause.isEmpty ? name : "\(name)<\(argClause)>")
        }
    }

    return nominalType.attempt <|> unitType

}

public let dateParser: GenericParser<String, (), Date> = lexer.integer >>- { year in
    symbol("-") *> lexer.integer >>- { month in
        symbol("-") *> lexer.integer >>- { day in
            lexer.integer >>- { hour in
                symbol(":") *> lexer.integer >>- {minute in
                    symbol(":") *> lexer.integer >>- { second in
                        symbol("+0000") >>- { _ in
                            let dateComponents = DateComponents(
                                calendar: .current,
                                timeZone: TimeZone(secondsFromGMT: 0),
                                year: year,
                                month: month,
                                day: day,
                                hour: hour,
                                minute: minute,
                                second: second,
                                nanosecond: 0
                            )

                            if dateComponents.isValidDate, let date = dateComponents.date {
                                return GenericParser(result: date)
                            } else {
                                return GenericParser.empty
                            }
                        }
                    }
                }
            }
        }
    }
}

public enum AppStateValue {

    case tuple([AppStateValue])
    case array([AppStateValue])
    case dictionary([(AppStateValue, AppStateValue)])
    case object([(String?, AppStateValue)])
    indirect case type(String, AppStateValue)
    case date(Date)
    case number(String)
    case string(String)
    case enumValue(String)
    case unparsed(String)

    public static let parser: GenericParser<String, (), AppStateValue> = {

        var appStateParser: GenericParser<String, (), AppStateValue>!

        _ = GenericParser.recursive { (rec: GenericParser<String, (), AppStateValue>) in
            
//            let unparsed: GenericParser<String, (), AppStateValue> = noneOf(",()[]").many1.stringValue.map {
//                AppStateValue.unparsed($0)
//            }

            let appStateDateParser: GenericParser<String, (), AppStateValue> =
                dateParser.map { AppStateValue.date($0) }

            let numberLiteral: GenericParser<String, (), AppStateValue> = lexer.number.map {

                let stringValue: String

                switch $0 {
                case .left(let int):
                    stringValue = "\(int)"
                case .right(let double):
                    stringValue = "\(double)"
                }

                return AppStateValue.number(stringValue)

            }

            let stringLiteral: GenericParser<String, (), AppStateValue> = lexer.stringLiteral.map {
                AppStateValue.string("\"\($0)\"")
            }

            // An enum value parses the same as a type with addition of true/false/nil
            // reserved keywords that are enums.
            let enumValue: GenericParser<String, (), AppStateValue> =
                (typeParser.attempt
                    <|>
                    stringParser("true")
                    <|>
                    stringParser("false")
                    <|>
                    stringParser("nil")
                ).map {
                    AppStateValue.enumValue($0)
                }

            let arrayLiteral: GenericParser<String, (), AppStateValue> =
                lexer.brackets(lexer.commaSeparated(rec)).map {
                    AppStateValue.array($0)
                }

            let tupleLiteral: GenericParser<String, (), AppStateValue> =
                lexer.parentheses(lexer.commaSeparated(rec)).map {
                    AppStateValue.tuple($0)
                }

            let nameValue: GenericParser<String, (), (AppStateValue, AppStateValue)> =
                rec >>- { name in
                    symbol(":") *> rec.map { value in (name, value) }
                }

            let dictionary1: GenericParser<String, (), [(AppStateValue, AppStateValue)]> =
                lexer.brackets(lexer.commaSeparated1(nameValue))

            let emtpyDictionary: GenericParser<String, (), [(AppStateValue, AppStateValue)]> =
                symbol("[") *> symbol(":") *> symbol("]") *> GenericParser(result: [])


            let dictionary: GenericParser<String, (), [(AppStateValue, AppStateValue)]> =
                (dictionary1.attempt <|> emtpyDictionary)

            let dictionaryLiteral = dictionary.map {
                AppStateValue.dictionary($0)
            }

            let fieldWithValue: GenericParser<String, (), (String, AppStateValue)> =
                lexer.identifier >>- { name in
                    symbol(":") *> rec.map { value in (name, value) }
                }

            let tupleValue: GenericParser<String, (), [(String?, AppStateValue)]> =
                lexer.parentheses(
                    lexer.commaSeparated(
                        fieldWithValue.map { (.some($0.0), $0.1) }.attempt
                            <|>
                            rec.map { (.none, $0) }
                    )
                )

            let nominalType: GenericParser<String, (), AppStateValue> =
                typeParser >>- { typeName in

                    tupleValue.map { (fields: [(String?, AppStateValue)]) -> AppStateValue in

                        AppStateValue.type(
                            typeName,
                            .object(fields)
                        )

                    }

                }

            appStateParser = nominalType

            return
                appStateDateParser.attempt
                <|>
                numberLiteral.attempt
                <|>
                stringLiteral.attempt
                <|>
                dictionaryLiteral.attempt
                <|>
                arrayLiteral.attempt
                <|>
                tupleLiteral.attempt
                <|>
                nominalType.attempt
                <|>
                enumValue
            //        enumValue.attempt
            //        <|>
            //        unparsed

        }

        return lexer.whiteSpace *> appStateParser
    }()

}

/// The identity function.
func id<Value>(_ value: Value) -> Value {
    return value
}

extension Array where Element == Array<String> {

    func flatten() -> [String] {
        flatMap(id)
    }

    func indent(_ indentation: String) -> [[String]] {

        self.map {
            $0.map {
                return indentation + $0
            }
        }

    }

    func commaSeparated() -> [[String]] {

        if count > 1 {

            return self.enumerated().map { (offset, value) in

                if offset < count - 1 {
                    if let last = value.last {
                        return value.dropLast() + [ "\(last), " ]
                    } else {
                        return value
                    }
                } else {
                    return value
                }

            }

        } else {

            return self

        }

    }

}

public struct PrettyPrinter {

    let indetation: String = " "
    let tabWidth: Int = 2
    let oneLineCharLimit: Int = 80

    let color = Color.white
    let typeColor = Color.extended(36)
    let valueColor = Color.extended(191)

    public init() {}

    private func spaces(indent: Int) -> String {

        String(repeating: " ", count: indent * tabWidth)

    }

    // Not perfect, but it works.
    public func prettyPrint(_ value: AppStateValue, _ level: Int = 0, highlight: Bool) -> [[String]] {

        switch value {

        case .unparsed(let text), .enumValue(let text), .string(let text), .number(let text):

            return [[ "\(text, color: valueColor, apply: highlight)" ]]

        case .date(let date):

            return [[ "\(date.description, color: valueColor, apply: highlight)" ]]

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

                    let first = prettyPrintedValue.flatten().map {$0.trimmingCharacters(in: .whitespaces)}.joined()
                    let rest = Array(prettyPrintedValue.dropFirst())

                    return [[ "\(prettyPrintedName): \(first)" ] + rest.flatten() ]

                }.commaSeparated()

                return [ [ "[" ] + fields.indent(spaces(indent: 1)).flatten() + [ "]" ] ]

            }

        }

    }

}
