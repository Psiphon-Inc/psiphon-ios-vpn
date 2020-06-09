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

import XCTest
import Utilities

final class CollectionAdditionsTests: XCTestCase {
    
    func testBasic() {
        let empty = [String]()
        let emptyChunked = empty.slice(atFirstOccurrence: { $0 == "one" })
        XCTAssert(emptyChunked == [])
        
        let a = ["one", "two", "three", "four"]
        
        let notFound = a.slice(atFirstOccurrence: { $0 == "ten" })
        XCTAssert(notFound.map({ Array($0) }) == [a])
        
        let chunkedFirst = a.slice(atFirstOccurrence: { $0 == "one" })
        XCTAssert(chunkedFirst == [[], ["one", "two", "three", "four"]])
        
        let chunkedLast = a.slice(atFirstOccurrence: { $0 == "four" })
        XCTAssert(chunkedLast == [["one", "two", "three"], ["four"]])
        
        let chunkedMiddle = a.slice(atFirstOccurrence: { $0 == "three" })
        XCTAssert(chunkedMiddle == [["one", "two"], ["three", "four"]])
    }
    
}
