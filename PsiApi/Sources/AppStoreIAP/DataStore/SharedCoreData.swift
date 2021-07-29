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

/// Represents authorization data that is shared between the host app
/// and the Network Extension through Core Data.
public struct SharedAuthorizationModel: Hashable {
    
    public let authorization: SignedAuthorizationData
    
    /// WebOrderLineItemID is `nil` for any non-subscription authorizations. (e.g. speed-boost).
    public let webOrderLineItemID: WebOrderLineItemID?
    
    public let psiphondRejected: Bool
    
    public init(
        authorization: SignedAuthorizationData,
        webOrderLineItemID: WebOrderLineItemID?,
        psiphondRejected: Bool
    ) {
        self.authorization = authorization
        self.webOrderLineItemID = webOrderLineItemID
        self.psiphondRejected = psiphondRejected
    }
    
}

public protocol SharedAuthCoreData: SharedCoreData {
    
    /// Queries Core Data for set of authorization with the given `accessTypes`.
    ///
    /// - Parameter psiphondRejected: If has value, filters authorizations based on psiphondRejected.
    ///                               If nil, returns authorizations with the given `accessTypes`.
    func getPersistedAuthorizations(
        psiphondRejected: Bool?,
        _ accessTypes: Set<Authorization.AccessType>,
        _ mainDispatcher: MainDispatcher
    ) -> Effect<Result<Set<SharedAuthorizationModel>, CoreDataError>>
    
    /// Updates persistent store with authorizations in `signedAuthorizations`.
    ///
    /// - Authorization that are in `sharedAuthorizationModels` but not persisted
    ///   are added to the persistent store.
    ///
    /// - Authorizations with given `accessTypes` that are in the persistent store,
    ///   but not found in `sharedAuthorizationModels` are removed from persistent store.
    ///
    /// - Authorizations that are already in persistent store are never updated, they can only be removed.
    ///
    /// - Parameter accessTypes: AccessType of authorizations to replace in the persistent store.
    ///                          This set must include AccessTypes of `sharedAuthorizationModels`.
    ///
    func syncAuthorizationsWithSharedCoreData(
        _ accessTypes: Set<Authorization.AccessType>,
        _ sharedAuthorizationModels: Set<SharedAuthorizationModel>,
        _ mainDispatcher: MainDispatcher
    ) -> Effect<Result<Bool, CoreDataError>>

}
