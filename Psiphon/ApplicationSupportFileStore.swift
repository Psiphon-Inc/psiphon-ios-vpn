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

import Foundation
import PsiApi

struct ApplicationSupportFileStore {
    
    enum Destination: Hashable {
        case psicash
        
        /// Returns attributes of current destination, it's relative path, whether it's a directory, and whether
        /// it should be backed up by iCloud.
        var attrs: (path: String, isDirectory: Bool, resourceValues: URLResourceValues) {
            switch self {
            case .psicash:
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                return (path: "psicash", isDirectory: true, resourceValues: values)
            }
        }
    }
    
    /// If non-nil, PsiCash file store root dir has been created.
    let psiCashFileStoreRootPath: String?
    let filesystemError: ErrorRepr?
    
    /// Sets up directories in Application Support directory. Initialization fails in case of a filesystem failure.
    init(fileManager: FileManager) {
        
        let appSupportUrl: URL
        
        do {
            appSupportUrl = try fileManager.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask,
                                                appropriateFor: nil,
                                                create: true)
        } catch {
            psiCashFileStoreRootPath = nil
            filesystemError = ErrorRepr(repr: String(describing: error))
            return
        }
        
        var psiCashURL = appSupportUrl.appendingPathComponent(
            Destination.psicash.attrs.path, isDirectory: true)
        
        do {
            // Creates PsiCash directory.
            try fileManager.createDirectory(atPath: psiCashURL.path,
                                            withIntermediateDirectories: false,
                                            attributes: nil)
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain &&
                (error as NSError).code == NSFileWriteFileExistsError {
                // Directory already exists.
            } else {
                psiCashFileStoreRootPath = nil
                filesystemError = ErrorRepr(repr: String(describing: error))
                return
            }
        }
        
        // Sets resource values for PsiCash directory and it's contents.
        do {
            try psiCashURL.setResourceValues(Destination.psicash.attrs.resourceValues)
            
            let filenames = try fileManager.contentsOfDirectory(atPath: psiCashURL.path)
            let fileURLs = filenames.map(psiCashURL.appendingPathComponent(_:))
            
            for url in fileURLs {
                var mutURL = url
                try mutURL.setResourceValues(Destination.psicash.attrs.resourceValues)
            }
            
            psiCashFileStoreRootPath = psiCashURL.path
            filesystemError = nil
            
        } catch {
            psiCashFileStoreRootPath = nil
            filesystemError = ErrorRepr(repr: String(describing: error))
        }
        
    }
    
}
