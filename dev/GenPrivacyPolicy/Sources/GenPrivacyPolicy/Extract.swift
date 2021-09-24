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

/// This file contains set of functions that extract data from the files hosted on psiphon-website

import Foundation
import SwiftyJSON
import SwiftSoup

/// Maps translations data from to a dictionary of LocalizedString objects
/// Check  https://github.com/Psiphon-Inc/psiphon-website/blob/master/_locales/en/messages.json
func translationToDict(_ data: Data) throws -> [TranslationKey: LocalizedString] {

    let json = try JSON(data: data).dictionaryValue
    
    return json.mapValues {
        LocalizedString(
            message: $0["message"].stringValue,
            description: $0["description"].string
        )
    }

}

/// Replaces instances of `"<%= @document.language %>"`
/// with valid Swift string interpolation syntax `"\(appLangKey)"`.
func replaceCoffeeScriptDocLang(_ template: String, appLangKey: String) throws -> String {
    
    var template = template
    
    // Matches "<%= @document.language %>"
    let pattern = #"<%[-=]\s+@document\.language\s+%>"#
    
    let regex = try NSRegularExpression(pattern: pattern, options: [])
    
    let results = regex.matches(in: template, options: [], range: NSMakeRange(0, template.count))
    
    // Since `template` is mutated, regexp matches are traversed in reverse order,
    // so that regpexp match ranges remain valid.
    for result: NSTextCheckingResult in results.reversed() {
        
        // Converts NSRange to Range<String.Index> for the given string.
        let matchRange = Range(result.range(at: 0), in: template)!
        
        // Replaces "<%= @document.language %>" with "\(appLangKey)" for the given appLangKey.
        template.replaceSubrange(matchRange, with: "\\(\(appLangKey))")
        
    }
    
    return template
    
}

/// Replaces embedded Coffee Script expressions of type `"<%[-=] @tt 'some-key' %>"` with
/// with valid Swift string interpolation syntax `"\(some_key)"`
func replaceCoffeeScriptLocalizations(_ template: String) throws -> (String, [TranslationKey: String]) {
    
    var template = template
    
    var translationKeysMap = [TranslationKey: String]()
    
    // Matches strings like "<%= @tt 'privacy-information-collected-psicash-para-4-item-1' %>"
    // TODO! find the missing element if [A-Za-z][A-Za-z0-9-]* is used.
    let pattern = #"<%[-=]\s+@tt\s+'(?<translationKey>.*)'\s+%>"#
    
    let regex = try NSRegularExpression(pattern: pattern, options: [])
    
    let results = regex.matches(in: template, options: [], range: NSMakeRange(0, template.count))
    
    // Since `template` is mutated, regexp matches are traversed in reverse order,
    // so that regpexp match ranges remain valid.
    for result: NSTextCheckingResult in results.reversed() {
        
        // We expect two ranges, first one is the range of the entire match
        // second one is the range of the captured group.
        guard result.numberOfRanges == 2 else {
            throw Failure(message: "Expected 2 ranges (the match, and the captured group)")
        }
        
        // Converts NSRange to Range<String.Index> for the given string.
        let matchRange = Range(result.range(at: 0), in: template)!
        let translationKeyRange = Range(result.range(at: 1), in: template)!
        
        let translationKey = String(template[translationKeyRange])
        
        // Creates a translation key compatible with Swift syntax by replacing dashes "-"
        // with underscores "_".
        let swiftTranslationKey = translationKey.replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        
        // Adds both keys to the map.
        translationKeysMap[translationKey] = swiftTranslationKey
        
        // Replaces string like "<%= @tt 'privacy-updates-head' %>"
        // in the template with swift string interpolation syntax \(privacy_updates_head)
        template.replaceSubrange(matchRange, with: "\\(\(swiftTranslationKey))")
        
    }
    
    return (template, translationKeysMap)
    
}
