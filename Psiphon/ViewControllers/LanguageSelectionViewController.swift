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

@objc final class LanguageSelectionViewController: PickerViewController {
    
    private let supportedLocalizations: SupportedLocalizations
    
    init(supportedLocalizations: SupportedLocalizations) {
        self.supportedLocalizations = supportedLocalizations
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.supportedLocalizations.readInAppSettingsSupportedLanguages()
        
        guard let languages = self.supportedLocalizations.languages else {
            fatalError()
        }
        
        let currentLangCode = self.supportedLocalizations.getCurrentLangCode()
        
        self.title = UserStrings.Select_language()
        
        // Finds the index of currently selected language.
        let maybeIndex = languages.firstIndex(where: { lang -> Bool in
            lang.code == currentLangCode
        })
        
        if let index = maybeIndex {
            self.selectedIndex = UInt(index)
        }
    }
    
    override func numberOfRows() -> UInt {
        return UInt(self.supportedLocalizations.languages?.count ?? 0)
    }
    
    override func bindData(to cell: UITableViewCell, atRow rowIndex: UInt) {
        guard let languages = self.supportedLocalizations.languages else {
            fatalError()
        }
        cell.textLabel!.text = languages[Int(rowIndex)].displayName
    }
    
    override func onSelectedRow(_ rowIndex: UInt) {
        
        guard let handler = self.selectionHandler else {
            fatalError()
        }
        
        guard let languages = self.supportedLocalizations.languages else {
            fatalError()
        }
        
        let selectedLang = languages[Int(rowIndex)]
        
        // Wraps selectedLang in a ObjC class, since handler's second argument is a reference type.
        handler(rowIndex, LanguageObjcWrapper(selectedLang), self)
        
    }
    
}
