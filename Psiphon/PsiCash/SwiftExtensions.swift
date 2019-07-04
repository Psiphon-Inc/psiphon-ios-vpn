//
//  SwiftExtensions.swift
//  Psiphon
//
//  Created by Amir Khan on 2019-07-04.
//  Copyright © 2019 Psiphon Inc. All rights reserved.
//

import Foundation

/// Applies transformer to the data and returns the result.
func new<T> (_ data: T, _ transformer: (T) -> (T)) -> T {
    return transformer(data)
}

extension Set {

    func add(_ newMember: Element) -> Set<Element> {
        var newValue = self
        newValue.insert(newMember)
        return newValue
    }

    func delete(_ element: Element) -> Set<Element> {
        var newValue = self
        newValue.remove(element)
        return newValue
    }

}
