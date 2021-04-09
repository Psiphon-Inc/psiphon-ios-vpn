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
import XCTest
import PsiApi

final class LocaleTests: XCTestCase {
    
    func testBCP47LangOnly() {
        
        let l = Locale(identifier: "en")
        
        XCTAssert(l.languageCode == "en")
        XCTAssert(l.scriptCode == nil)
        XCTAssert(l.regionCode == nil)
        
        XCTAssert(l.bcp47Identifier == "en")
        
    }
    
    func testBCP47NoRegion() {
        
        let l = Locale(identifier: "zh-Hant")
        
        XCTAssert(l.languageCode == "zh")
        XCTAssert(l.scriptCode == "Hant")
        XCTAssert(l.regionCode == nil)
        
        XCTAssert(l.bcp47Identifier == "zh-Hant")
        
    }
    
    func testBCP47NoScript() {
        
        let l = Locale(identifier: "en-CA")
        
        XCTAssert(l.languageCode == "en")
        XCTAssert(l.scriptCode == nil)
        XCTAssert(l.regionCode == "CA")
        
        XCTAssert(l.bcp47Identifier == "en-CA")
        
    }
    
    func testBCP47() {
        
        let l = Locale(identifier: "zh-Hant-HK")
        
        XCTAssert(l.languageCode == "zh")
        XCTAssert(l.scriptCode == "Hant")
        XCTAssert(l.regionCode == "HK")
        
        XCTAssert(l.bcp47Identifier == "zh-Hant-HK")
        
    }
    
    func testBCP47WithPrivateSubtag() {
        
        let l = Locale(identifier: "zh-TW-x-java")
        
        XCTAssert(l.languageCode == "zh")
        XCTAssert(l.scriptCode == nil)
        XCTAssert(l.regionCode == "TW")
        
        XCTAssert(l.bcp47Identifier == "zh-TW")
        
    }
    
}
