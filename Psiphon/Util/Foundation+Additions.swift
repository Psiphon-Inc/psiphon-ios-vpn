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

// MARK: Types

/// The identity function.
func id<Value>(_ value: Value) -> Value {
    return value
}

struct Indexed<Value> {
    let index: Int
    let value: Value
}

/// A not so efficient queue.
public struct Queue<Element> {
    private var items = [Element]()

    var count: Int { items.count }
    
    var isEmpty: Bool { items.isEmpty }
    
    /// - Complexity: O(n) where n is the size of the queue.
    mutating func enqueue(_ item: Element) {
        items.insert(item, at: 0)
    }
    
    /// - Complexity: O(1)
    mutating func dequeue() -> Element? {
        guard !items.isEmpty else {
            return .none
        }
        return items.removeLast()
    }
}

extension Queue: Equatable where Element: Equatable {}

public struct NonEmpty<Element> {
    private var storage: [Element]

    public init(_ head: Element, _ tail: [Element]) {
        self.storage = [head] + tail
    }

    public init?(array: [Element]?) {
        guard let array = array else {
            return nil
        }
        guard array.count > 0 else {
            return nil
        }
        self.storage = array
    }
    
    public var head: Element {
        self.storage.first!
    }
    
    public var tail: ArraySlice<Element> {
        self.storage.dropFirst()
    }

    public var count: Int {
        self.storage.count
    }

    public subscript(index: Int) -> Element {
        get {
            self.storage[index]
        }
        set(newValue) {
            self.storage[index] = newValue
        }
    }

}

extension NonEmpty: Equatable where Element: Equatable {}
extension NonEmpty: Hashable where Element: Hashable {}

extension NonEmpty: Collection {
    public func index(after i: Int) -> Int { self.storage.index(after: i) }

    public var startIndex: Int { self.storage.startIndex }

    public var endIndex: Int { self.storage.endIndex }
}


/// Represents a value that is only accessible if the given predicate returns true at the time of the call.
public struct PredicatedValue<Value: Equatable, PredicateArg: Any> {
    private let value: Value
    private let predicate: (PredicateArg) -> Bool

    public init(value: Value, predicate: @escaping (PredicateArg) -> Bool) {
        self.value = value
        self.predicate = predicate
    }

    public func getValue(_ input: PredicateArg) -> Value? {
        guard predicate(input) else {
            return .none
        }
        return value
    }

    public func map<U: Equatable>(_ transformer: (Value) -> U) -> PredicatedValue<U, PredicateArg> {
        return PredicatedValue<U, PredicateArg>(value: transformer(self.value), predicate: self.predicate)
    }

}

extension PredicatedValue: Equatable {

    public static func == (lhs: PredicatedValue<Value, PredicateArg>,
                    rhs: PredicatedValue<Value, PredicateArg>) -> Bool {
        lhs.value == rhs.value
    }

}

/// Represents unit `()` type that is `Equatable`.
/// - Bug: This is a hack since `()` (and generally tuples) do not conform to `Equatable`.
public enum Unit: Equatable {
    case unit
}

public enum Either<A, B> {
    case left(A)
    case right(B)
}

extension Either: Equatable where A: Equatable, B: Equatable {}
extension Either: Hashable where A: Hashable, B: Hashable {}

public extension Either {

    /// If `A` and `B` are not `Equatable`, we can at least check equality of `self` and  provided `value`
    /// ignoring the associated value.
    func isEqualCase(_ value: Either<A, B>) -> Bool {
        switch (self, value) {
        case (.left, .left):
            return true
        case (.right, .right):
            return true
        default:
            return false
        }
    }
}

/// `HashableView` provides an alternative view for the same value's hash.
public struct HashableView<Value: Hashable, Alternative: Hashable>: Hashable {
    
    let value: Value
    private let hashKeyPath: KeyPath<Value, Alternative>
    
    init(_ value: Value, _ hashKeyPath: KeyPath<Value, Alternative>) {
        self.value = value
        self.hashKeyPath = hashKeyPath
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value[keyPath: lhs.hashKeyPath] == rhs.value[keyPath: rhs.hashKeyPath]
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value[keyPath: hashKeyPath].hashValue)
    }
    
}

public extension Set {

    /// Inserts `newMember` into the set if it is not contained in the set.
    /// If the set contains a member with value under path `equalPath` equal to `newMember`'s value under the same
    /// key path, then the contained member is removed from the set, and `newMember` is inserted.
    /// - Returns: true if `newMember` is inserted.
    mutating func insert<T: Hashable>(
        orReplaceIfEqual equalPath: KeyPath<Element, T>, _ newMember: Element
    ) -> Bool {
        guard !contains(newMember) else {
            return false
        }
        
        var equalMember: Element? = .none
        for member in self {
            if member[keyPath: equalPath] == newMember[keyPath: equalPath] {
                equalMember = member
                break
            }
        }
        
        if let equalMember = equalMember {
            remove(equalMember)
        }
        
        let (inserted, _) = insert(newMember)
        return inserted
    }

}

public extension Collection {

    func map<U>(_ path: KeyPath<Element, U>) -> [U] {
        return self.map { (element: Element) -> U in
            let a = element[keyPath: path]
            return a
        }
    }

    /// Returns element at the given index if it is in the collection, otherwise return nil.
    subscript(maybe i: Index) -> Element? {
        return indices.contains(i) ? self[i] : .none
    }
}

public extension Result {

    var success: Bool {
        switch self {
        case .success(_): return true
        case .failure(_): return false
        }
    }
    
    func projectSuccess() -> Success? {
        switch self {
        case .success(let value):
            return value
        case .failure(_):
            return .none
        }
    }

    func projectError() -> Error? {
        switch self {
        case .success:
            return .none
        case .failure(let error):
            return error
        }
    }
    
    func dropSuccessValue() -> Result<(), Failure> {
        switch self {
        case .success(_):
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
    
}

public extension Result where Success == () {
    
    func mapToUnit() -> Result<Unit, Failure> {
        self.map { _ in
            .unit
        }
    }

}

func join<A>(_ optional: Optional<Optional<A>>) -> Optional<A> {
    switch optional {
    case .some(.some(let value)):
        return value
    default:
        return .none
    }
}

public extension Optional where Wrapped == Bool {

    /// Returns `nilValue` if nil, otherwise returns wrapped value.
    func ifNil(_ nilValue: Bool) -> Bool {
        switch self {
        case .none:
            return nilValue
        case let .some(value):
            return value
        }
    }

}

/// A type that can be binded to to change it's state.
public protocol Bindable {
    associatedtype BindingType: Equatable
    typealias Binding = (BindingType) -> Void

    func bind(_ newValue: BindingType)
}

typealias PendingResult<Success: Equatable, Failure: Error & Equatable> = Pending<Result<Success, Failure>>

/// A type that is isomorphic to Optional type, intended to represent computations that are "pending" before finishing.
public enum Pending<Completed> {
    case pending
    case completed(Completed)
}

extension Pending: Equatable where Completed: Equatable {}
extension Pending: Hashable where Completed: Hashable {}

extension Pending {
    
    func map<B>(_ f: (Completed) -> B) -> Pending<B> {
        switch self {
        case .pending:
            return .pending
        case .completed(let completed):
            return .completed(f(completed))
        }
    }
    
}

/// Represents a type that has a default init constructor.
protocol DefaultValue {
    init()
}

extension Array: DefaultValue {}

/// Represents a computation that carries the success result in a subsequent pending state.
typealias PendingWithLastSuccess<Success: DefaultValue, Failure: Error> =
    PendingValue<Success, Result<Success, Failure>>

extension PendingWithLastSuccess {
    
    static func pending<Success: DefaultValue, Failure: Error>(
        previousValue: PendingWithLastSuccess<Success, Failure>
    ) -> PendingWithLastSuccess<Success, Failure> {
        switch previousValue {
        case .pending(_):
            return previousValue
        case let .completed(.success(success)):
            return .pending(success)
        case .completed(.failure(_)):
            return .pending(.init())
        }
    }
    
}


// TODO: Combine `Pending` and `PendingValue` into one type.
enum PendingValue<Pending, Completed> {
    case pending(Pending)
    case completed(Completed)
}

extension PendingValue: Equatable where Pending: Equatable, Completed: Equatable {}


extension PendingValue {
    
    func map<A, B>(
        pending transformPending: (Pending) -> A,
        completed transformCompleted: (Completed) -> B
    ) -> PendingValue<A, B> {
        switch self {
        case .pending(let value):
            return .pending(transformPending(value))
        case .completed(let value):
            return .completed(transformCompleted(value))
        }
    }
    
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

// Copied from https://stackoverflow.com/questions/47714560/how-to-convert-dispatchtimeinterval-to-nstimeinterval-or-double
extension DispatchTimeInterval {

    func toDouble() -> TimeInterval? {
        var result: Double? = 0

        switch self {
        case .seconds(let value):
            result = Double(value)
        case .milliseconds(let value):
            result = Double(value)*0.001
        case .microseconds(let value):
            result = Double(value)*0.000001
        case .nanoseconds(let value):
            result = Double(value)*0.000000001

        case .never:
            result = nil
        @unknown default:
            fatalError("Unknown value '\(String(describing: self))'")
        }

        return result
    }
}

// MARK: File operations

func plistReader<DecodeType: Decodable>(key: String, toType: DecodeType.Type) throws -> DecodeType {
    // TODO: Add bundle dependency as an argument.
    guard let url = Bundle.main.url(forResource: key, withExtension: "plist") else {
        fatalError("'\(key).plist' is not valid")
    }

    let data = try Data(contentsOf: url)
    let decoder = PropertyListDecoder()
    return try decoder.decode(toType, from: data)
}

// MARK: Coding

extension JSONDecoder {
    
    static func makeIso8601JSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    
}

extension JSONEncoder {
    
    static func makeIso8601Encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    
}

// MARK: User Defaults

/// Represents a type that can be stored by `UserDefaults` (aka `NSUserDefaults`).
/// Check `NSUserDefaults` documentation for information on supported types:
/// https://developer.apple.com/documentation/foundation/userdefaults
protocol UserDefaultsPropertyListType {}

extension NSData: UserDefaultsPropertyListType {}
extension NSString: UserDefaultsPropertyListType {}
extension NSNumber: UserDefaultsPropertyListType {}
extension NSDate: UserDefaultsPropertyListType {}
extension NSArray: UserDefaultsPropertyListType {}
extension NSDictionary: UserDefaultsPropertyListType {}

extension Data: UserDefaultsPropertyListType {}
extension String: UserDefaultsPropertyListType {}
extension Date: UserDefaultsPropertyListType {}
extension Array: UserDefaultsPropertyListType {}
extension Dictionary: UserDefaultsPropertyListType {}

@propertyWrapper
struct UserDefault<T: UserDefaultsPropertyListType> {
    let key: String
    let defaultValue: T
    let store: UserDefaults

    init(_ store: UserDefaults, _ key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
        self.store = store
    }

    var wrappedValue: T {
        get {
            return store.object(forKey: key) as? T ?? defaultValue
        }
        set {
            store.set(newValue, forKey: key)
        }
    }
}

@propertyWrapper
struct JSONUserDefault<T: Codable> {
    let logType = LogTag("JSONUserDefault")
    let key: String
    let defaultValue: T
    let store: UserDefaults

    init(_ store: UserDefaults, _ key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
        self.store = store
    }

    var wrappedValue: T {
        get {
            guard let data = store.data(forKey: key) else {
                return defaultValue
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                PsiFeedbackLogger.error(withType: logType,
                                        message: "failed to decode data",
                                        object: error)
                return defaultValue
            }
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                store.set(data, forKey: key)
            } catch {
                PsiFeedbackLogger.error(withType: logType,
                                        message: "failed to encode data",
                                        object: error)
                store.set(nil, forKey: key)
            }

        }
    }

    func sync() {
        store.synchronize()
    }

    public var projectedValue: Self {
        get { self }
    }
}

// MARK: Debug Utils
public extension URLRequest {
    func debugPrint() {
        print("""
            HTTP Request:
            URL:
            \(self.url!.absoluteString)
            Header:
            \(String(describing: self.allHTTPHeaderFields!))
            Body:
            \(String(data: self.httpBody!, encoding: .utf8)!)
            """)
    }
}

// MARK: Reference management

/// A protocol that is class-bound.
/// - Discussion: This enables `where` clause to match protocol that are class-bound.
protocol ClassBound: class {}

/// `WeakRef` holds a weak reference to the underlying type.
/// - Discussion: This type is useful to provide access to resource that might other be leaked.
final class WeakRef<Wrapped: ClassBound> {
    
    weak var weakRef: Wrapped?
    
    init(_ ref: Wrapped) {
        self.weakRef = ref
    }
}

extension WeakRef: Equatable where Wrapped: Equatable {
    
    static func == (lhs: WeakRef<Wrapped>, rhs: WeakRef<Wrapped>) -> Bool {
        return lhs.weakRef == rhs.weakRef
    }
    
}
