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
import AppStoreIAP


/// Notes on Core Data.
///
/// - Core Data is not thread-safe, and each NSManagedObjectContext has an associated queue (main queue by default)
///
/// - NSPredicate:
///   Using %@ for variable subsctitution automatically quotes the passed-in string, otherwise values need to be quoted.

@objc final class SharedCoreData_Impl: NSObject, SharedAuthCoreData {
    
    var viewContext: NSManagedObjectContext? {
        switch self.containerWrapper {
        case .success(let persistentContainer):
            return persistentContainer.container.viewContext
        case .failure(_):
            return nil
        }
    }
    
    lazy var containerWrapper: Result<PersistentContainerWrapper, SystemError<Int>> = {
        var error: NSError? = nil
        let container = PersistentContainerWrapper.load(&error)
        
        if let error = error {
            let error = SystemError<Int>.make(error)
            return .failure(error)
            
        } else if let container = container {
            return .success(container)
            
        } else {
            fatalError("container is nil but no error returned")
        }
    }()
    
    override init() {
        super.init()
    }
    
    @objc func destroyPersistentStore() throws {
        switch self.containerWrapper {
        case .success(let containerWrapper):
            
            guard let storeURL = AppFiles.sharedSqliteDB() else {
                throw ErrorMessage("Failed to get shared SQL DB URL")
            }
            
            try containerWrapper.container.persistentStoreCoordinator
                .destroyPersistentStore(at: storeURL,
                                        ofType: NSSQLiteStoreType,
                                        options: nil)
            
        case .failure(let error):
            throw error
        }
    }
    

    
    func getPersistedAuthorizations(
        psiphondRejected: Bool?,
        _ accessTypes: Set<Authorization.AccessType>,
        _ mainDispatcher: MainDispatcher
    ) -> Effect<Result<Set<SharedAuthorizationModel>, CoreDataError>> {
        
        // Effect is dispatched on the main thread, since SharedCoreData has it's viewContext
        // configured as a NSMainQueueConcurrencyType context.
        
        Effect.deferred(dispatcher: mainDispatcher) { [weak self] fulfill in
            
            // Main Thread sanity check.
            if Debugging.mainThreadChecks {
                precondition(Thread.isMainThread, "Effect not on main thread")
            }
            
            // Gets NSManagedObjectContext if Core Data stack is fully initialized.
            guard let context = self?.viewContext else {
                fulfill(.failure(.stackNotInitialized))
                return
            }
            
            // Builds Core Data predicate
            let accessTypePred = makePredicate(accessTypes: accessTypes)
            let psiphondRejectedPred = makePredicate(psiphondRejected: psiphondRejected ?? false)
            
            // Fetches set of subscription authorizations.
            let request = SharedAuthorization.fetchRequest() as! NSFetchRequest<SharedAuthorization>
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates:
                                                        [accessTypePred, psiphondRejectedPred])
            
            do {
                
                var models = [SharedAuthorizationModel]()
                
                let decoder = JSONDecoder.makeRfc3339Decoder()
                
                let persistedSubscriptionAuths = try context.fetch(request)
                
                for persistedAuth in persistedSubscriptionAuths {
                    
                    let model = try persistedAuth.makeSharedAuthorizationModel(
                        rfc3339JSONDecoder: decoder)
                    
                    models.append(model)
                    
                }
                
                fulfill(.success(Set(models)))
                
            } catch {
                
                let systemError = SystemError<Int>.make(error as NSError)
                fulfill(.failure(.error(systemError)))
            }
            
        }
        
    }
    
    func syncAuthorizationsWithSharedCoreData(
        _ accessTypes: Set<Authorization.AccessType>,
        _ sharedAuthorizationModels: Set<SharedAuthorizationModel>,
        _ mainDispatcher: MainDispatcher
    ) -> Effect<Result<Bool, CoreDataError>> {
        
        // Effect is dispatched on the main thread, since SharedCoreData has it's viewContext
        // configured as a NSMainQueueConcurrencyType context.
        
        Effect.deferred(dispatcher: mainDispatcher) { [weak self] fulfill in
            
            // Main Thread sanity check.
            if Debugging.mainThreadChecks {
                precondition(Thread.isMainThread, "Effect not on main thread")
            }
            
            // Gets NSManagedObjectContext if Core Data stack is fully initialized.
            guard let context = self?.viewContext else {
                fulfill(.failure(.stackNotInitialized))
                return
            }
            
            // Fetches set of all authorizations for the given access types.
            let request = SharedAuthorization.fetchRequest() as! NSFetchRequest<SharedAuthorization>
            request.predicate = makePredicate(accessTypes: accessTypes)
            
            do {
                
                let persistedValues = try context.fetch(request)
                
                // Deletes values from persistent store whose id
                // has not matching record in sharedAuthorizationModels.
                for persistedValue in persistedValues {
                    
                    guard let persistedAuthID = persistedValue.id else {
                        // id field is nonnull.
                        fatalError("programming error")
                    }
                    
                    let found = sharedAuthorizationModels.contains {
                        $0.authorization.decoded.authorization.id == persistedAuthID
                    }
                    
                    if !found {
                        context.delete(persistedValue)
                    }
                   
                }
                
                // Sets valuesNotPersisted to values of sharedAuthorizationModels
                // that are not persisted with Core Data.
                let valuesNotPersisted = sharedAuthorizationModels.filter { element in
                    
                    let persisted = persistedValues.contains(where: { sharedAuthorization in
                        sharedAuthorization.id! == element.authorization.decoded.authorization.id
                    })
                    
                    return !persisted
                }
                
                // Registers new SharedAuthorization objects with the given Core Data context,
                // for all the authorizations in signedAuthorizations that are not persisted already.
                for sharedAuthModel in valuesNotPersisted {
                    let _ = sharedAuthModel.makeSharedAuthorizationObj(context: context)
                }
                
                // Commits any changes that have been made.
                if context.hasChanges {
                    try context.save()
                    fulfill(.success(true))
                } else {
                    fulfill(.success(false))
                }
                
            } catch {
                
                let systemError = SystemError<Int>.make(error as NSError)
                fulfill(.failure(.error(systemError)))
                
            }
            
            
        }
        
    }
    
    #if DEBUG
    func printAllAuthorizations() {
        guard let context = self.viewContext else {
            print("* nil context")
            return
        }
        let allData = SharedAuthorization.fetchRequest() as! NSFetchRequest<SharedAuthorization>
        do {
            let allData = try context.fetch(allData)
            for (i, data) in allData.enumerated() {
                print("* row \(i): \(data.id!) - \(data.accessType!) - \(data.psiphondRejected) - \(String(describing: data.webOrderLineItemId))")
            }
        } catch {
            print("* failed: \(error)")
        }
    }
    #endif
    
    
}

extension SharedAuthorizationModel {
    
    /// Makes SharedAuthorization object that is a NSManagedObject.
    func makeSharedAuthorizationObj(context: NSManagedObjectContext) -> SharedAuthorization {
        let sharedAuth = SharedAuthorization(context: context)
        sharedAuth.id = authorization.decoded.authorization.id
        sharedAuth.accessType = authorization.decoded.authorization.accessType.rawValue
        sharedAuth.rawValue = authorization.rawData
        sharedAuth.webOrderLineItemId = webOrderLineItemID?.rawValue
        sharedAuth.psiphondRejected = psiphondRejected
        sharedAuth.expires = authorization.decoded.authorization.expires
        return sharedAuth
    }
    
}

extension SharedAuthorization {
    
    /// - Parameter decoder: JSON decoder with custom RFC3339 date decoder.
    func makeSharedAuthorizationModel(
        rfc3339JSONDecoder: JSONDecoder
    ) throws -> SharedAuthorizationModel {
            
        let signedAuth = try SignedAuthorization.make(
            base64String: self.rawValue!, rfc3339JSONDecoder: rfc3339JSONDecoder)
        
        let signedAuthData = SignedData(rawData: self.rawValue!, decoded: signedAuth)
        
        let webOrderLineItemID = WebOrderLineItemID(rawValue: self.webOrderLineItemId ?? "")
        
        return SharedAuthorizationModel(
            authorization: signedAuthData,
            webOrderLineItemID: webOrderLineItemID,
            psiphondRejected: self.psiphondRejected
        )
        
    }
    
}

extension Authorization.AccessType {
    
    static var appleSubscription: String {
        if Debugging.devServers {
            return Authorization.AccessType.appleSubscriptionTest.rawValue
        } else {
            return Authorization.AccessType.appleSubscription.rawValue
        }
    }
    
    static var speedBoost: String {
        if Debugging.devServers {
            return Authorization.AccessType.speedBoostTest.rawValue
        } else {
            return Authorization.AccessType.speedBoost.rawValue
        }
    }
    
}

fileprivate func makePredicate(accessTypes: Set<Authorization.AccessType>) -> NSCompoundPredicate {
    precondition(!accessTypes.isEmpty)
    let subs = accessTypes.map {
        NSPredicate(format: "accessType == %@", $0.rawValue)
    }
    return NSCompoundPredicate(orPredicateWithSubpredicates: subs)
}

fileprivate func makePredicate(psiphondRejected: Bool) -> NSPredicate {
    NSPredicate(format:"psiphondRejected == \(psiphondRejected ? 1 : 0)")
}
