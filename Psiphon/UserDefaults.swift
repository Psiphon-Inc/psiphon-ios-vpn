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

// TODO! Consider using ZippyJSON

@propertyWrapper
struct UserDefault<T> {
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
            return try! JSONDecoder().decode(T.self, from: data)
        }
        set {
            let data = try! JSONEncoder().encode(newValue)
            store.set(data, forKey: key)
        }
    }
}

class UserDefaultsConfig {

    @JSONUserDefault(.standard, "subscription_data_v1", defaultValue: .none)
    var subscriptionData: SubscriptionData?

}
