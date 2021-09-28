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
import CoreData

/// Represents set of all possible Core Data errors.
public enum CoreDataError: HashableError {
    /// Core Data stack is not initialized.
    case stackNotInitialized
    /// Wraps Core Data error.
    case error(SystemError<Int>)
}

@objc public protocol SharedCoreData {
    
    /// Managed object context for the app's main queue.
    /// This object should be used only on main queue, and should not be passed around
    /// arround to other threads.
    /// - Important: Only use the correct queue for the context.
    var viewContext: NSManagedObjectContext? { get }
    
    /// Deletes persistent store.
    func destroyPersistentStore() throws
    
}
