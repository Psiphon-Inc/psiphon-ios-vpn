/*
* Copyright (c) 2019, Psiphon Inc.
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

/// Applies transformer to the data and returns the result.
func map<T> (_ data: T, _ transform: (T) -> (T)) -> T {
    return transform(data)
}

extension Set {

    func add(_ newMember: Element) -> Self {
        var newValue = self
        newValue.insert(newMember)
        return newValue
    }

    func delete(_ element: Element) -> Self {
        var newValue = self
        newValue.remove(element)
        return newValue
    }

}

/// A result that is progressing towards completion. It can either be inProgress, or completed with `Result` associated value.
enum ProgressiveResult<Success, Failure> where Failure: Error {
    /// Result is in progress.
    case inProgress
    /// A failure, storing a `Failure` value.
    case completed(Result<Success, Failure>)
}

/// A type that is isomorphic to Optional type, intended to represent computations that are "in progress" before finishing.
enum Progressive<Result> {
    case inProgress
    case done(Result)
}

/// Enables dictionary set/get directly with enums that their raw value type matches the dictionary key.
extension Dictionary where Key: ExpressibleByStringLiteral {

    subscript<T>(index: T) -> Value? where T: RawRepresentable, T.RawValue == Key {
        get {
            return self[index.rawValue]
        }
        set(newValue) {
            self[index.rawValue] = newValue
        }
    }

}

/// Create a DispatchSourceTimer that on
class SingleFireTimer {

    private let timer: DispatchSourceTimer

    /// - Parameter handler: Uses default `DispatchSourceTimer` dispatch queue.
    init(deadline: TimeInterval, leeway: DispatchTimeInterval = .seconds(1),
         _ handler: @escaping () -> Void) {

        timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .intervalFromNow(deadline),
                       repeating: .never,
                       leeway: leeway)
        timer.setEventHandler(handler: handler)
        timer.resume()
    }

    deinit {
        timer.setEventHandler(handler: {})

        // It's an error on call cancel on a suspended timer.
        // Details here: https://forums.developer.apple.com/thread/15902
        timer.cancel()
    }

}

extension DispatchTime {

    /// Creats DispatchTime by adding `interval` to `DispatchTime.now()`.
    /// - Important: Sub-millisecond precision is lost in the current implementation.
    static func intervalFromNow(_ interval: TimeInterval) -> DispatchTime {
        let intervalInMilliseconds = 1000 * interval

        if intervalInMilliseconds == Double.infinity {
            fatalError("interval '\(interval)' is too large")
        }

        return DispatchTime.now() + DispatchTimeInterval.milliseconds(Int(intervalInMilliseconds))
    }

}

// MARK: File operations

func plistReader(key: String) throws -> [String] {
    guard let url = Bundle.main.url(forResource: key, withExtension: "plist") else {
        fatalError("'\(key).plist' is not valid")
    }

    let data = try Data(contentsOf: url)
    let decoder = PropertyListDecoder()
    return try decoder.decode([String].self, from: data)
}
