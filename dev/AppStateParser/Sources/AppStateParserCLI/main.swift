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
import ArgumentParser
import AppStateParser
import CustomDump

func runParser(input: String) -> Either<ParseError, AppStateValue> {
    let result = AppStateValue.parser.runSafe(userState: (), sourceName: "", input: input)
    
    guard case .right(let parseTree) = result else {
        return result
    }
    
    return .right(recursiveApply(parseTree: parseTree))
    
}

func recursiveApply(parseTree: AppStateValue) -> AppStateValue {
    
    switch parseTree {
        
    case .tuple(let array):
        return .tuple(array.map { recursiveApply(parseTree: $0) })
        
    case .array(let array):
        return .array(array.map { recursiveApply(parseTree: $0) })
        
    case .dictionary(let uniqueKeysWithValues):
        return .dictionary(
            uniqueKeysWithValues.map { key, value in
                (recursiveApply(parseTree: key), recursiveApply(parseTree: value))
            }
        )
        
    case .object(let uniqueKeysWithValues):
        return .object(
            uniqueKeysWithValues.map { key, value in (key, recursiveApply(parseTree: value)) }
        )
        
    case .jsonObject(let uniqueKeysWithValues):
        return .jsonObject(
            uniqueKeysWithValues.map { key, value in (key, recursiveApply(parseTree: value)) }
        )
        
    case .type(let typeName, let fields):
        return .type(typeName, recursiveApply(parseTree: fields))
        
    case .date(let date):
        return .date(date)
        
    case .number(let number):
        return .number(number)
        
    case .string(let string):
        
        // Tries to unquote and parse the string if possible.
        
        guard string.contains("\"") else {
            return .string(string)
        }
                
        let unquoted = string.replacingOccurrences(of: "\\\"", with: "\"")
        
        switch AppStateValue.parser.runSafe(userState: (), sourceName: "", input: unquoted) {
            
        case .left(_):
            // Failed to further parse unquoted string
            return .string(string)
            
        case .right(let parsed):
            
            switch parsed {
                
            case .string(let string), .enumValue(let string):
                // Did not make progress. String was returned as string.
                // If a string turned into an enum, then it was probably a string,
                // and didn't need further parsing.
                return .string(string)
                
            default:
                // Was able to parse further. Let's keep going.
                return recursiveApply(parseTree: parsed)
                
            }
            
        }
        
    case .enumValue(let enumValue):
        return .enumValue(enumValue)
        
    case .custom(let customValue):
        return .custom(customValue)
    }
    
}

struct CLI: ParsableCommand {

    @Flag(name: [.customLong("nohl", withSingleDash: true)],
          help: "Disable syntax highlighting.")
    var noHighlight: Bool = false

    @Flag(name: [.short, .long], help: "Unquotes the input.")
    var unquote: Bool = false

    @Flag(help: "Prints parse tree.")
    var printParseTree: Bool = false
    
    @Option(name: [.short, .customLong("timezone", withSingleDash: true)],
            help: "Formats dates in the given time zone (e.g. \"America/Toronto\")")
    var timeZone: String?

    @Option(name: [.short, .customLong("file", withSingleDash: true)],
            help: "Input file path.")
    var filePath: String?

    @Argument(help: "AppState string to parse.")
    var string: String?

    mutating func run() throws {

        let prettyPrinter = PrettyPrinter(timeZone: timeZone)

        var input: String

        if let filePath = filePath {

            guard case .none = self.string else {
                throw ValidationError("Cannot provide both <string> argument and -file option.")
            }

            input = try String(contentsOfFile: filePath, encoding: .utf8)

        } else if let string = string {

            input = string

        } else {

            throw ValidationError("Must provide either <string> argument or -file option.")

        }

        input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = input.replacingOccurrences(of: "\\n", with: "")
        
        if unquote {
            input = input.replacingOccurrences(of: "\\\"", with: "\"")
        }
        
        let result = runParser(input: input)

        switch  result {

        case .left(let error):
            print("Parser Error:", error)

        case .right(let value):

            if printParseTree {

                var dumpedValue: String = ""
                customDump(value, to: &dumpedValue)

                dumpedValue = dumpedValue
                    .replacingOccurrences(of: "AppStateValue", with: "")

                print("\n🛂", dumpedValue, "\n")

            }

            print(prettyPrinter.prettyPrint(value, highlight: !noHighlight).map {
                    $0.joined(separator: "\n")
            }.joined(separator: "\n"))

        }

    }

}

CLI.main()
