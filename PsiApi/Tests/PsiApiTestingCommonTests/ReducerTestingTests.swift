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
import PsiApi
@testable import PsiApiTestingCommon

enum Action: Equatable {
    case inc
    case dec
}

struct State: Equatable {
    var count: Int
}

final class ReducerTestsTests: XCTestCase {

    func testBasicTestReducerWithActions() {
        
        let reducer: Reducer<State, Action, ()> = { state, action, _ -> [Effect<Action>] in
            switch action {
            case .inc:
                state.count += 1
                
                if state.count < 46 {
                    return [ Effect(value: .inc) ]
                } else {
                    return [ Effect(value: .dec) ]
                }
            case .dec:
                state.count -= 1
                return []
            }
        }
                
        let result = testReducerRec(State(count: 42), .inc, (), reducer)
        
        XCTAssert(result == [
            ReducerTestResult(State(count: 43), [[.value(.inc), .completed]]),
            ReducerTestResult(State(count: 44), [[.value(.inc), .completed]]),
            ReducerTestResult(State(count: 45), [[.value(.inc), .completed]]),
            ReducerTestResult(State(count: 46), [[.value(.dec), .completed]]),
            ReducerTestResult(State(count: 45), [])
            ])
    }
    
}
