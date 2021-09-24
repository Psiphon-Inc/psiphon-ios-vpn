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
import ArgumentParser
import SwiftSoup



struct CLI: ParsableCommand {
    
    @Option(help: "Key for the app language")
    var appLanguageKey: String
    
    @Option(help: "Privacy policy HTML .eco template file")
    var privacyPolicyTemplateURL: URL
    
    @Option(help: "Translations URL")
    var translationsURL: URL
    
    mutating func run() throws {
        
        guard let templateData = downloadFile(url: privacyPolicyTemplateURL) else {
            throw Failure(message: "Failed to download Privacy Policy file")
        }
        
        guard let translationsData = downloadFile(url: translationsURL) else {
            throw Failure(message: "Failed to download translations file")
        }
        
        let translations = try translationToDict(translationsData)
        
        // ---
        
        guard let templateHTML = String(data: templateData, encoding: .utf8) else {
            throw Failure(message: "Failed to decode data with UTF-8")
        }
        
        let (templateHtmlWithSwiftSyntax, translationKeysMap) =
        try replaceCoffeeScriptLocalizations(
            try replaceCoffeeScriptDocLang(templateHTML, appLangKey: appLanguageKey))
        
        let doc = try SwiftSoup.parse(templateHtmlWithSwiftSyntax)
        
        // Selects second set of nested div that contain relevant Privacy Policy information
        let ppSection = try doc.select("div>div")[2]
        
        // Removes HTML elements with no text (e.g. <span> elements).
        try removeElementsWithNoText(ppSection)
        
        let acc = StringBuilder()
        acc.appendLine("static func privacy_policy_...() -> String {")
        acc.appendLine("")
        
        for (translationKey, swiftTranslationKey) in translationKeysMap {
            
            let localizedString = translations[translationKey]!
            
            // Escapes quotes.
            let value = localizedString.message.replacingOccurrences(of: "\"", with: "\\\"")
            let comment = (localizedString.description ?? "").replacingOccurrences(of: "\"", with: "\\\"")
            
            acc.appendLine("let \(swiftTranslationKey) = NSLocalizedString(\"\(translationKey)\", tableName: nil, bundle: Bundle.main,")
            acc.appendLine("value: \"\(value)\",")
            acc.appendLine("comment: \"\(comment)\")")
            
        }
        
        acc.appendLine("")
        acc.appendLine("    return \"\"\"")
        acc.appendLine("        \(try ppSection.html())")
        acc.appendLine("    \"\"\"")
        acc.appendLine("}")
        
        print(acc.toString())
        
    }
    
}

CLI.main()
