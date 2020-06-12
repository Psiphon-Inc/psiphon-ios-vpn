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
import ReactiveSwift
@testable import Testing

class TestUtilTests: XCTestCase {
    
    func testGenerator() {
        let seq = Array(1...10)
        let generator = Generator(sequence: seq)
        
        var generatedSeq = [Int]()
        while let next = generator.next() {
            generatedSeq.append(next)
        }
        
        XCTAssert(seq == generatedSeq)
    }
    
    func testSignalProducerJust() {
        // Arrange
        let expectedTotalTimeLowerBound = 10 * 0.01  // 10 elements * 10 milliseconds
        
        // Act
        let start = CFAbsoluteTimeGetCurrent()
        
        let result = SignalProducer<Int, Never>
            .just(values: Array(1...10), withInterval: .milliseconds(10))
            .collectForTesting(timeout: 1.0)
        
        let end = CFAbsoluteTimeGetCurrent()
        
        let diff = end - start
        XCTAssert(diff >= expectedTotalTimeLowerBound, "total time diff: '\(diff)'")
        XCTAssert(diff < expectedTotalTimeLowerBound * 1.2,
                  "exceeded lower bound by more than 20%: '\(diff)'")
                
        XCTAssert(
            result == [
                .value(1), .value(2), .value(3), .value(4), .value(5),
                .value(6), .value(7), .value(8), .value(9), .value(10),
                .completed
            ],
            "Got result '\(result)'"
        )
    }

}
