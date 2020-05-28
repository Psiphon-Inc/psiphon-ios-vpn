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

public func XCTFatal(message: String = "") -> Never {
    XCTFail(message)
    fatalError()
}

public struct Generator<Value>: IteratorProtocol {
    
    private let sequence: [Value]
    private var index = 0
    
    public var exhausted: Bool {
        return sequence.count == index
    }
    
    public init(sequence: [Value]) {
        self.sequence = sequence
    }
    
    public mutating func next() -> Value? {
        guard index < sequence.count else {
            return nil
        }
        defer {
            index += 1
        }
        return sequence[index]
    }
    
}

extension Generator {
    
    public static func empty() -> Generator<Value> {
        return Generator(sequence: [])
    }
    
}

public let globalTestingScheduler = QueueScheduler(qos: .userInteractive,
                                                   name: "PsiphonTestsScheduler",
                                                   targeting: .global())

extension SignalProducer where Error: Equatable {
    
    public typealias CollectedEvents = [Signal<Value, SignalError>.Event]
    
    public enum SignalError: Swift.Error, Equatable {
        /// Signal did not complete within the timeout interval.
        case signalTimedOut
        /// Wrapped upstream error.
        case signalError(Error)
    }
    
    public func collectForTesting(
        timeout: TimeInterval = 1.0
    ) -> CollectedEvents {
        
        let result = self.mapError { signalError -> SignalError in
            return .signalError(signalError)
        }
        .timeout(after: timeout, raising: .signalTimedOut, on: globalTestingScheduler)
        .materialize()
        .collect()
        .single()
        
        guard case let .success(value) = result else {
            XCTFail()
            return []
        }
        
        return value
    }
    
    public static func just(values: [Value], withInterval interval: DispatchTimeInterval) -> Self {
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
