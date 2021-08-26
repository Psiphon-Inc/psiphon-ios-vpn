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

let lexer = GenericTokenParser(languageDefinition: LanguageDefinition<()>.swift)

// Java style is used since it is more permissive, without having to write our own string literal parser.
let stringLiteralLexemeParser = GenericTokenParser(languageDefinition: LanguageDefinition<()>.javaStyle).stringLiteral

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

    let cSynthDecl: GenericParser<String, (), String> =
        (symbol("__C_Synthesized.related decl 'e' for") *> rec).map {
            "__C_Synthesized.related decl 'e' for \($0)"
        }

    return
        cSynthDecl.attempt
        <|>
        nominalType.attempt
        <|>
        unitType

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
    case jsonObject([(String, AppStateValue)])
    indirect case type(String, AppStateValue)
    case date(Date)
    case number(String)
    case string(String)
    case enumValue(String)
    case custom(String)

    public static let parser: GenericParser<String, (), AppStateValue> = {

        let appStateParser: GenericParser<String, (), AppStateValue> =
        GenericParser.recursive { (rec: GenericParser<String, (), AppStateValue>) in
            
            // Parses values like `123 bytes`.
            let bytesParser: GenericParser<String, (), AppStateValue> =
            lexer.number >>- { number in
                
                let numBytes: Int
                
                switch number {
                case .left(let int):
                    numBytes = int
                case .right(_): /* Double value */
                    return GenericParser.fail("Expected integer number of bytes")
                }
                
                return lexer.whiteSpace *> lexer.symbol("bytes").map { _ in .custom("\(numBytes) bytes") }
                
            }
            
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

            let stringLiteral: GenericParser<String, (), AppStateValue> =
            stringLiteralLexemeParser.map {
                AppStateValue.string("\($0)")
            }
            
            let stringWrappedValue: GenericParser<String, (), AppStateValue> =
            lexer.symbol("\"") *> rec.map { parsed in
                // If the parsed value in quotations is an enum, then it was probably a string.
                if case .enumValue(let enumValue) = parsed {
                    return .string(enumValue)
                } else {
                    return parsed
                }
            } <* lexer.symbol("\"")
            
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
            
            let jsonField: GenericParser<String, (), (String, AppStateValue)> =
            lexer.stringLiteral >>- { name in
                    symbol(":") *> rec.map { value in (name, value) }
                }
            
            let jsonObj1: GenericParser<String, (), [(String, AppStateValue)]> =
                lexer.braces(lexer.commaSeparated1(jsonField))

            let jsonObjLiteral = jsonObj1.map {
                AppStateValue.jsonObject($0)
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

            return
                appStateDateParser.attempt
                <|>
                bytesParser.attempt
                <|>
                numberLiteral.attempt
                <|>
                dictionaryLiteral.attempt
                <|>
                arrayLiteral.attempt
                <|>
                jsonObjLiteral.attempt
                <|>
                tupleLiteral.attempt
                <|>
                nominalType.attempt
                <|>
                stringWrappedValue.attempt
                <|>
                stringLiteral.attempt
                <|>
                enumValue

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
