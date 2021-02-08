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
import ArgumentParser
import AppStateParser

struct CLI: ParsableCommand {

    @Flag(name: [.customLong("nohl", withSingleDash: true)],
          help: "Disable syntax highlighting.")
    var noHighlight: Bool = false

    @Flag(name: [.short, .long], help: "Unquotes the input.")
    var unquote: Bool = false

    @Flag(help: "Prints parse tree.")
    var printParseTree: Bool = false

    @Option(name: [.short, .customLong("file", withSingleDash: true)],
            help: "Input file path.")
    var filePath: String?

    @Argument(help: "AppState string to parse.")
    var string: String?

    mutating func run() throws {

        let prettyPrinter = PrettyPrinter()

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

        if unquote {
            input = input.replacingOccurrences(of: "\\\"", with: "\"")
        }

        let result = AppStateValue.parser.runSafe(userState: (), sourceName: "", input: input)

        switch  result {

        case .left(let error):
            print("Parser Error:", error)

        case .right(let value):

            if printParseTree {

                var dumpedValue: String = ""
                dump(value, to: &dumpedValue)

                dumpedValue = dumpedValue
                    .replacingOccurrences(of: "AppStateParser.AppStateValue", with: "")

                print("\n🛂", dumpedValue, "\n")

            }

            print(prettyPrinter.prettyPrint(value, highlight: !noHighlight).map {
                    $0.joined(separator: "\n")
            }.joined(separator: "\n"))

        }

    }

}

CLI.main()
