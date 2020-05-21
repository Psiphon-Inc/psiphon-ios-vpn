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

func XCTFatal(message: String = "") -> Never {
    XCTFail(message)
    fatalError()
}

struct Generator<Value>: IteratorProtocol {
    
    private let sequence: [Value]
    private var index = 0
    
    init(sequence: [Value]) {
        self.sequence = sequence
    }
    
    mutating func next() -> Value? {
        guard index < sequence.count else {
            return nil
        }
        defer {
            index += 1
        }
        return sequence[index]
    }
    
}

let globalTestingScheduler = QueueScheduler(qos: .userInteractive,
                                     name: "PsiphonTestsScheduler",
                                     targeting: .global())

extension SignalProducer where Error: Equatable {
    
    enum SignalError: Swift.Error, Equatable {
        /// Signal did not complete within the timeout interval.
        case signalTimedOut
        /// Wrapped upstream error.
        case signalError(Error)
    }
    
    func collectForTesting(
        timeout: TimeInterval = 1.0
    ) -> NonEmpty<Signal<Value, SignalError>.Event> {
        
        let result = self.mapError { signalError -> SignalError in
            return .signalError(signalError)
        }
        .timeout(after: timeout, raising: .signalTimedOut, on: globalTestingScheduler)
        .materialize()
        .collect()
        .single()
        
        guard let nonEmptyArray = NonEmpty(array: result?.projectSuccess()) else {
            fatalError("Expected non-empty result array: '\(String(describing: result))'")
        }
        return nonEmptyArray
    }
    
    static func just(values: [Value], withInterval interval: DispatchTimeInterval) -> Self {
        SignalProducer { observer, lifetime in
            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now(), repeating: interval, leeway: .nanoseconds(0))
            
            var generator = Generator(sequence: values)
            timer.setEventHandler {
                guard let nextValue = generator.next() else {
                    observer.sendCompleted()
                    return
                }
                observer.send(value: nextValue)
            }
            
            timer.resume()
            
            lifetime += AnyDisposable {
                timer.cancel()
            }
        }
    }
    
}
