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
import PsiApi
import Utilities

enum AdControllerStatus<LoadError: HashableError, PresentationError: HashableError>: Equatable {
    
    enum PresentationStatus: Equatable {
        
        /// Ad has been successfully loaded, but not presented yet.
        case notPresented
        
        /// Ad is currently presenting.
        case presenting
        
        /// Ad failed to present.
        case failedToPresent(PresentationError)
       
        /// Ad was presented and dismissed.
        case dismissed
        
    }
    
    /// Ad controller has not received any requests for an ad.
    case noAdsLoaded
    
    /// Ad load has been initiated and is in progress.
    case loading
    
    /// Ad load failed.
    case loadFailed(ErrorEvent<LoadError>)
    
    /// An ad has been successfully loaded.
    case loadSucceeded(PresentationStatus)
    
}
