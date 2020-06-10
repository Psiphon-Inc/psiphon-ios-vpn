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
import Testing
import Rfc3339CTimestamp

struct DateContainer: Codable {
    let date: Date
}

class RFC3339Tests: XCTestCase {
    
    let testData: [(String, TimeInterval, Date.SecondsFractionPrecision, precisionLoss: Bool)] = [
        ("2020-05-25T15:53:19.172092229Z", 1590421999.172092229, .nine, true),
        ("2020-05-25T15:53:19.172092Z", 1590421999.172092, .six, false),
        ("2020-05-25T15:53:19.172Z", 1590421999.172, .three, false),
        ("2020-05-25T15:57:58Z", 1590422278.0, .zero, false)
    ]

    func testParsing() {
        // Tests parsing of RFC3339 formatted dates.
        // Since date object returns unix time in seconds with type `Double`,
        // there will be precision loss with timestamps with nanosecond precision.
        
        for (rfc3339String, unixTime,_, _) in testData {
            guard let parsed = Date.parse(rfc3339Date: rfc3339String) else {
                XCTFatal()
            }
            XCTAssert(parsed.timeIntervalSince1970 == unixTime)
        }
    }
    
    func testFormatting() {
                
        for (rfc3339String, unixTime, precision, precisionLoss) in testData {
            
            // Skips over data where there is precision loss in converting value to Date object.
            if precisionLoss {
                continue
            }
            
            let date = Date(timeIntervalSince1970: unixTime)
            
            guard let formatted = date.formatRFC3339(secondsFractionPrecision: precision) else {
                XCTFatal()
            }
            
            XCTAssert(rfc3339String == formatted,
                      "'\(rfc3339String)' is not equal to '\(formatted)'")
        }
        
    }
    
    func testJsonRfc3339Decoder() {
        
        let decoder = JSONDecoder.makeRfc3339Decoder()
        
        for (rfc3339String, unixTime, _, _) in testData {
            guard let encodedData = #"{"date":"\#(rfc3339String)"}"#.data(using: .utf8) else {
                XCTFatal()
            }
            
            guard let decoded = try? decoder.decode(DateContainer.self, from: encodedData) else {
                XCTFatal()
            }
            
            XCTAssert(decoded.date.timeIntervalSince1970 == unixTime)
        }
        
    }
    
    func testJsonRfc3339Encoder() {
            
        for (rfc3339String, unixTime, precision, precisionLoss) in testData {
            
            // Skips over data where there is precision loss in converting value to Date object.
            if precisionLoss {
                continue
            }
            
            let date = DateContainer(date: Date(timeIntervalSince1970: unixTime))
            let expectedEncodedValue = #"{"date":"\#(rfc3339String)"}"#
            
            let encoder = JSONEncoder.makeRfc3339Encoder(precision: precision)
            guard let encoded = try? String(data: encoder.encode(date), encoding: .utf8) else {
                XCTFatal()
            }
            
            XCTAssert(encoded == expectedEncodedValue,
                      "\(encoded) is not equal to \(expectedEncodedValue)")
        }
        
    }

}
