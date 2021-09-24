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
import ArgumentParser
import SwiftSoup

extension URL: ExpressibleByArgument {
    
    public init?(argument: String) {
        self.init(string: argument)
    }
    
}

struct Failure: Error {
    let message: String
}

func downloadFile(url: URL) -> Data? {
    
    var result: Data? = nil
    
    let sem = DispatchSemaphore(value: 0)
    
    let dataTask = URLSession.shared.dataTask(with: url) {
        dataOrNil, responseOrNil, errorOrNil in
        
        defer {
            sem.signal()
        }
        
        guard errorOrNil == nil else { return }
        
        guard
            let response = responseOrNil as? HTTPURLResponse,
            (200..<299).contains(response.statusCode)
        else { return }
        
        result = dataOrNil
        
    }
    
    dataTask.resume()
    
    sem.wait()
    
    return result
    
}

/// Traverses are children of `element` depth-first, and calls `apply` on them.
func walkAndApply(_ element: Element, apply: (Element) throws -> Void) throws {
    
    for childElem in element.children() {
        
        if childElem.children().count > 0 {
            try walkAndApply(childElem, apply: apply)
        }
        
        try apply(childElem)
        
    }
    
}

/// Removed children of `element` that have no text (this includes text of their children).
func removeElementsWithNoText(_ element: Element) throws {

    try walkAndApply(element) { childElem in
        
        if !childElem.hasText() {
            try childElem.remove()
        }

    }

}

// MARK: Translations

typealias TranslationKey = String

struct LocalizedString {
    /// Localized string
    let message: String
    /// Comments for the translator
    let description: String?
}

