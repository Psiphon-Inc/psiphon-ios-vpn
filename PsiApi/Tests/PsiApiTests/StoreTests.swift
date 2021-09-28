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
@testable import PsiApi

final class StoreTests: XCTestCase {
    
    func testProjectionCallCount() {
        
        let counterReducer = Reducer<Int, Void, Void> { state, _, _ in
            state += 1
            return []
        }
        
        var numCalls1 = 0
        _ = Store(initialValue: 0, reducer: counterReducer, dispatcher: MainDispatcher(), environment: erase)
            .projection(value: { (count: Int) -> Int in
                numCalls1 += 1
                return count
            })
        
        XCTAssert(numCalls1 == 1)
    }
    
    func testProjectionValueUpdate() {
        
        // Tests if all projections of a store have their local
        // value updated after any state change.
        
        let counterReducer = Reducer<Int, Void, Void> { state, _, _ in
            state += 1
            return []
        }

        let store1 = Store(initialValue: 0, reducer: counterReducer, dispatcher: MainDispatcher(), environment: erase)
        
        let store2 = store1.projection(value: { (count: Int) -> Int in
                return count
        })
        
        let store3 = store2.projection(value: { (count: Int) -> Int in
                return count
        })
        
        let store4 = store3.projection(value: { (count: Int) -> Int in
                return count
        })

        XCTAssert(store1.value == 0)
        XCTAssert(store2.value == 0)
        XCTAssert(store3.value == 0)
        XCTAssert(store4.value == 0)

        _ = store1.syncSend(())

        XCTAssert(store1.value == 1)
        XCTAssert(store2.value == 1)
        XCTAssert(store3.value == 1)
        XCTAssert(store4.value == 1)

        _ = store2.syncSend(())
        
        XCTAssert(store1.value == 2)
        XCTAssert(store2.value == 2)
        XCTAssert(store3.value == 2)
        XCTAssert(store4.value == 2)

        _ = store3.syncSend(())

        XCTAssert(store1.value == 3)
        XCTAssert(store2.value == 3)
        XCTAssert(store3.value == 3)
        XCTAssert(store4.value == 3)

        _ = store4.syncSend(())
        
        XCTAssert(store1.value == 4)
        XCTAssert(store2.value == 4)
        XCTAssert(store3.value == 4)
        XCTAssert(store4.value == 4)
        
    }
    
    func testProjectionCallCount2() {
        
        let counterReducer = Reducer<Int, Void, Void> { state, _, _ in
            state += 1
            return []
        }

        var numCalls1 = 0
        var numCalls2 = 0
        var numCalls3 = 0

        let store1 = Store(initialValue: 0, reducer: counterReducer, dispatcher: MainDispatcher(), environment: { _ in () })
        
        let store2 = store1.projection(value: { (count: Int) -> Int in
                numCalls1 += 1
                return count
        })
        
        let store3 = store2.projection(value: { (count: Int) -> Int in
                numCalls2 += 1
                return count
        })
        
        let store4 = store3.projection(value: { (count: Int) -> Int in
                numCalls3 += 1
                return count
        })

        XCTAssert(numCalls1 == 1)
        XCTAssert(numCalls2 == 1)
        XCTAssert(numCalls3 == 1)

        _ = store4.syncSend(())

        XCTAssert(numCalls1 == 2)
        XCTAssert(numCalls2 == 2)
        XCTAssert(numCalls3 == 2)

        _ = store4.syncSend(())

        XCTAssert(numCalls1 == 3)
        XCTAssert(numCalls2 == 3)
        XCTAssert(numCalls3 == 3)

        _ = store4.syncSend(())
        
        XCTAssert(numCalls1 == 4)
        XCTAssert(numCalls2 == 4)
        XCTAssert(numCalls3 == 4)

        _ = store4.syncSend(())
        
        XCTAssert(numCalls1 == 5)
        XCTAssert(numCalls2 == 5)
        XCTAssert(numCalls3 == 5)
    }
    
    func testProjectionCallCount3() {
        
        struct State: Equatable {
            var mainStore = 0
            var subStore = 0
        }
        
        enum Action {
            case mainStoreAction
            case subStoreAction
        }
        
        let counterReducer = Reducer<State, Action, Void> { state, action, _ in
            switch action {
            case .mainStoreAction:
                state.mainStore += 1
            case .subStoreAction:
                state.subStore += 1
            }
            return []
        }

        var numCalls1 = 0
        var numCalls2 = 0

        let store1 = Store(initialValue: State(), reducer: counterReducer, dispatcher: MainDispatcher(), environment: { _ in () })
        
        let store2 = store1.projection(value: { (globalState: State) -> Int in
            return globalState.subStore
        }, action: { () in
            return .subStoreAction
        })
        
        store1.$value.signalProducer.startWithValues { _ in
            numCalls1 += 1
        }
        
        store2.$value.signalProducer.startWithValues { _ in
            numCalls2 += 1
        }
        
        XCTAssert(store1.value.mainStore == 0)
        XCTAssert(store2.value == 0)
        
        XCTAssert(numCalls1 == 1)
        XCTAssert(numCalls2 == 1)

        _ = store1.syncSend(.mainStoreAction)
        
        XCTAssert(store1.value.mainStore == 1)
        XCTAssert(store2.value == 0)

        XCTAssert(numCalls1 == 2)
        XCTAssert(numCalls2 == 1)

        _ = store2.syncSend(())
        
        XCTAssert(store1.value.mainStore == 1)
        XCTAssert(store2.value == 1)

        XCTAssert(numCalls1 == 3)
        XCTAssert(numCalls2 == 2)

        _ = store1.syncSend(.mainStoreAction)
        
        XCTAssert(store1.value.mainStore == 2)
        XCTAssert(store2.value == 1)
        
        XCTAssert(numCalls1 == 4)
        XCTAssert(numCalls2 == 2)

        _ = store2.syncSend(())
        
        XCTAssert(store1.value.mainStore == 2)
        XCTAssert(store2.value == 2)

        XCTAssert(numCalls1 == 5)
        XCTAssert(numCalls2 == 3)
    }

}
