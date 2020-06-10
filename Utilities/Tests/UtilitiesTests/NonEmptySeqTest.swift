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
@testable import Utilities

class NonEmptySeqTest: XCTestCase {

    func testJSONEncoding() throws {

        let x: NonEmptySeq<String> = .cons("1",
                                           .cons("2",
                                                 .cons("3",
                                                       .elem("4"))))

        // Test encoding

        var jsonData: Data

        do {
            jsonData = try JSONEncoder().encode(x)
        } catch {
            XCTFail("Failed to encode list as JSON: \(error.localizedDescription)")
            return
        }

        if let jsonString = String(data: jsonData, encoding: .utf8) {
            XCTAssertEqual(jsonString,
                          "{\"cons\":{\"x\":\"1\",\"xs\":{\"cons\":{\"x\":\"2\",\"xs\":{\"cons\":{\"x\":\"3\",\"xs\":{\"elem\":\"4\"}}}}}}}")

        } else {
           XCTFail("Failed to encode json data")
           return
        }

        // Test decoding

        do {

            let y: NonEmptySeq<String> = try JSONDecoder().decode(NonEmptySeq<String>.self, from: jsonData)

            XCTAssertEqual(x, y)

        } catch {
            XCTFail("Failed to decode json data")
            return
        }
    }
    
    static var allTests = [
        ("testJSONEncoding", testJSONEncoding),
    ]

}
