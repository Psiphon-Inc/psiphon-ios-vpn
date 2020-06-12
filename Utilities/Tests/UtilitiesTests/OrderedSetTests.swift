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

/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Utilities

typealias OrderedSet = Utilities.OrderedSet

class OrderedSetTests: XCTestCase {
    func testBasics() {
        // Create an empty set.
        var set = OrderedSet<String>()
        XCTAssertTrue(set.isEmpty)
        XCTAssertEqual(set.contents, [])

        // Create a new set with some strings.
        set = OrderedSet(["one", "two", "three"])
        XCTAssertFalse(set.isEmpty)
        XCTAssertEqual(set.count, 3)
        XCTAssertEqual(set[0], "one")
        XCTAssertEqual(set[1], "two")
        XCTAssertEqual(set[2], "three")
        XCTAssertEqual(set.contents, ["one", "two", "three"])

        // Try adding the same item again - the set should be unchanged.
        XCTAssertEqual(set.append("two"), false)
        XCTAssertEqual(set.count, 3)
        XCTAssertEqual(set[0], "one")
        XCTAssertEqual(set[1], "two")
        XCTAssertEqual(set[2], "three")

        // Remove the last element.
        let three = set.removeLast()
        XCTAssertEqual(set.count, 2)
        XCTAssertEqual(set[0], "one")
        XCTAssertEqual(set[1], "two")
        XCTAssertEqual(three, "three")

        // Remove all the objects.
        set.removeAll(keepingCapacity: true)
        XCTAssertEqual(set.count, 0)
        XCTAssertTrue(set.isEmpty)
        XCTAssertEqual(set.contents, [])
    }
    
    func testReplacement() {
        let original = OrderedSet(["one", "two", "three"])
        var mutable = original
        XCTAssert(original == mutable)
        
        let badInsert = mutable.replace("four", with: "five")
        XCTAssertFalse(badInsert)
        XCTAssert(mutable == original)
        
        let inserted = mutable.replace("three", with: "six")
        XCTAssertTrue(inserted)
        XCTAssert(mutable.contents == ["one", "two", "six"])
        XCTAssertTrue(mutable.contains("one"))
        XCTAssertTrue(mutable.contains("two"))
        XCTAssertTrue(mutable.contains("six"))
        XCTAssertFalse(mutable.contains("three"))
    }
    
}
