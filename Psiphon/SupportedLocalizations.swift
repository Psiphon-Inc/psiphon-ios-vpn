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

struct Language: Equatable {
    let code: String
    let displayName: String
}

extension Language {
    static let defaultLanguageCode = ""
    static let defaultLanguageDisplayNameKey = "DEFAULT_LANGUAGE"
}

extension Language {
    
    static func defaultLanguage(bundle: PsiphonCommonLibBundle) -> Language {
        let displayName = bundle.localizedString(forKey: defaultLanguageDisplayNameKey)
        return Language(code: defaultLanguageCode, displayName: displayName)
    }
    
}

/// Objcective-C wrapper for the Language struct.
@objc final class LanguageObjcWrapper: NSObject {
    let value: Language
    init(_ value: Language) {
        self.value = value
    }
}

final class SupportedLocalizations {
    
    private(set) var languages: [Language]? = nil
    private let userDefaultsConfig: UserDefaultsConfig
    private let mainBundle: Bundle
    private let psiphonCommonLibBundle: PsiphonCommonLibBundle
    
    init(userDefaultsConfig: UserDefaultsConfig, mainBundle: Bundle) {
        self.userDefaultsConfig = userDefaultsConfig
        self.mainBundle = mainBundle
        self.psiphonCommonLibBundle = PsiphonCommonLibBundle(mainBundle: mainBundle)!
    }
    
    func getCurrentLangCode() -> String {
        
        guard let languages = self.languages else {
            fatalError()
        }
        
        let currentLangCode = self.userDefaultsConfig.appLanguage
        
        let supportedLang = languages.first {
            $0.code == currentLangCode
        }
        
        switch supportedLang {
        case .none:
            // Language code stored in user's defaults is no longer supported.
            return Language.defaultLanguageCode
        case.some(let lang):
            return lang.code
        }
        
    }
    
    func readInAppSettingsSupportedLanguages() {

        let url = self.mainBundle.url(forResource: "Root.inApp",
                                      withExtension: "plist",
                                      subdirectory: "InAppSettings.bundle")!
        
        let data = try! Data(contentsOf: url)
        
        let plistData = try! PropertyListSerialization.propertyList(
            from: data, options: .mutableContainers, format: nil
        ) as! [String: Any]
        
        // Traverses InAppSettings.bundle/Root.inApp.plist to get to
        // the "SETTINGS_LANGUAGE" dict (3rd index of array under key "PreferenceSpecifiers").
        let preferenceSpecifiers = plistData["PreferenceSpecifiers"] as! [Any]
        let settingsLanguage = preferenceSpecifiers[3] as! [String: Any]
        let titles = settingsLanguage["Titles"] as! [[String: String]]
        let langCodes = settingsLanguage["Values"] as! [String]
        let langDisplayName = titles.map { $0["Title"]! }
        
        // Checks if the correct dict from the plist file is being read.
        let title = settingsLanguage["Title"] as! String
        guard title == "SETTINGS_LANGUAGE" else {
            fatalError()
        }
        
        self.languages = zip(langCodes, langDisplayName).map { code, displayName in
            if code == Language.defaultLanguageCode &&
                displayName == Language.defaultLanguageDisplayNameKey {
                return Language.defaultLanguage(bundle: self.psiphonCommonLibBundle)
            } else {
                return Language(code: code, displayName: displayName)
            }
        }
    }
    
}
