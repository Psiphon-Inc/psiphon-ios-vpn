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

#import "AuthorizationStore.h"
#import "PsiphonConfigReader.h"
#import "PsiFeedbackLogger.h"
#import "PersistentContainerWrapper.h"
#import "Authorization.h"

PsiFeedbackLogType const AuthorizationStoreLogType = @"AuthorizationStore";

@implementation AuthorizationStore {
    
    // Authorizations selected for use by Psiphon tunnel.
    // Key is accessType value.
    // Thread-safety: This object should onyl be accessed through NSManagedObjectContext's queue.
    NSMutableDictionary<NSString *, Authorization *> *_Nonnull selectedAuthorizations;
    
}

- (instancetype)init {
    self = [super init];
    if (self) {
        selectedAuthorizations = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - Private

- (NSManagedObjectContext *_Nullable)getManagedObjectContext {
    NSError *error = nil;
    PersistentContainerWrapper *containerWrapper = [PersistentContainerWrapper load:&error];
    
    if (error != nil) {
        [PsiFeedbackLogger errorWithType:AuthorizationStoreLogType
                                 message:@"Failed to load Core Data persistent container"
                                  object:error];
        return nil;
    }
    
    if (containerWrapper == nil) {
        // Programming error, value should never be nil.
        [PsiFeedbackLogger errorWithType:AuthorizationStoreLogType
                                 message:@"Unexpected nil PersistentContainer"];
        return nil;
    }
    
    return containerWrapper.container.viewContext;
}

#pragma mark - Public

- (NSString *)getSponsorId:(PsiphonConfigSponsorIds *)psiphonConfigSponsorIds
           updatedSharedDB:(PsiphonDataSharedDB *)sharedDB {
    
    __block NSString *result = psiphonConfigSponsorIds.defaultSponsorId;
    
    NSManagedObjectContext *context = [self getManagedObjectContext];
    
    if (context == nil) {
        return result;
    }
    
    [context performBlockAndWait:^{
        if (selectedAuthorizations[SubscriptionAccessType] != nil) {
            result = psiphonConfigSponsorIds.subscriptionSponsorId;
        }
    }];
    
    // Store current sponsor ID used for use by container.
    [sharedDB setCurrentSponsorId:result];

    return result;
    
}

- (NSSet<NSString *> *_Nullable)getNewAuthorizations {
    
    // Loads Core Data persistent container.
    NSManagedObjectContext *context = [self getManagedObjectContext];
    
    if (context == nil) {
        return nil;
    }
    
    // Tracks if set of authorizations have changed since last call to this function.
    // If authorizations have not changed, this function returns nil.
    __block BOOL authorizationsChanged = FALSE;
    
    __block NSSet<NSString *> *result = nil;
    
    [context performBlockAndWait:^{
        
        for (NSString *accessType in @[SubscriptionAccessType, SpeedBoostAccessType]) {
            
            // Requests all authorization from Core Data for the given accessType, that are not
            // already rejected by Psiphon servers.
            
            NSFetchRequest<SharedAuthorization *> *request = [SharedAuthorization fetchRequest];
            request.predicate = [NSPredicate predicateWithFormat:
                                 @"accessType == %@ AND psiphondRejected == 0",
                                 accessType];
            
            NSError *error = nil;
            NSArray<SharedAuthorization *> *fetchResult = [context executeFetchRequest:request
                                                                                 error:&error];
            
            if (error != nil) {
                [PsiFeedbackLogger errorWithType:AuthorizationStoreLogType
                                         message:@"Failed to execute authorization fetch request"
                                          object:error];
                return;
            }
            
            // Updates selectedAuthorizations dictionary based on fetched results.
            //
            // Possible cases:
            //
            // - Case 1: selectedAuthorizations[accessType] == nil and fetchResult is empty:
            //   No authorization was selected before, and no authorization are persisted.
            //   `authorizationsChanged = FALSE`
            //
            // - Case 2: selectedAuthorizations[accessType] != nil and fetchResult is empty:
            //   An authorization was selected before, but no authorizations are persisted.
            //   Authorization was then removed by the host app.
            //   `authorizationsChanged = TRUE`
            //
            // - Case 3: selectedAuthorizations[accessType] == nil and fetchResult != empty:
            //   There is a new persisted authorization.
            //   `authorizationsChanged = TRUE`
            //
            // - Case 4: selectedAuthorizations[accessType] != nil and fetchResult != empty:
            //
            //   - Case 4.1: If the authorizations are equal:
            //     Previously selected authorization is not removed from persistence store.
            //     `authorizationsChanged = FALSE`
            //
            //   - Case 4.2: If the authorizations are not equal:
            //     Authorization value has changed, and the new authorization should be used.
            //     `authorizationsChanged = TRUE`
            //
            
            
            // Case 1
            if ([fetchResult count] == 0 && selectedAuthorizations[accessType] == nil) {
                [PsiFeedbackLogger
                 infoWithType:AuthorizationStoreLogType
                 format:@"No authorizations for accessType '%@'", accessType];
                continue;
            }

            BOOL alreadySelected = FALSE;
            
            // Sets alreadySelected to TRUE if selectedAuthorizations[accessType] value
            // is already contained in fetchResult.
            if (selectedAuthorizations[accessType] != nil) {
                for (SharedAuthorization *persisted in fetchResult) {
                    if ([persisted.id isEqualToString:selectedAuthorizations[accessType].ID]) {
                        alreadySelected = TRUE;
                        break;
                    }
                }
            }
            
            // Case 4.1
            if (alreadySelected) {
                continue;
            }

            // Case 2, 3, 4.2
            SharedAuthorization *selected = [fetchResult firstObject];
            selectedAuthorizations[accessType] = [Authorization makeFromSharedAuthorization:selected];
            
            authorizationsChanged = TRUE;
            
        }
        
        if (!authorizationsChanged) {
            [PsiFeedbackLogger infoWithType:AuthorizationStoreLogType
                                     message:@"No new authorizations found."];
            result = nil;
            return;
        }
        
        NSMutableArray<NSString *> *rawValues = [NSMutableArray array];
        for (Authorization *authorization in [selectedAuthorizations allValues]) {
            [rawValues addObject:authorization.rawValue];
            [PsiFeedbackLogger infoWithType:AuthorizationStoreLogType
                                     format:@"New Authorization with ID: %@", authorization.ID];
        }
        
        result = [NSSet setWithArray:rawValues];
    }];
    
    return result;
    
}

- (BOOL)setActiveAuthorizations:(NSArray<NSString *> *_Nonnull)activeAuthorizationIds {
    
    // Sets "psiphondRejected" field to TRUE for rejected authorizations,
    // and sets selectedAuthorizations values to nil for the rejected authorizations.
    
    // Loads Core Data persistent container.
    NSManagedObjectContext *context = [self getManagedObjectContext];
    
    if (context == nil) {
        return FALSE;
    }
    
    // This flag indicates if one of the rejected authorization was an
    // apple-subscription authorization.
    __block BOOL subscriptionRejected = FALSE;
    
    [context performBlockAndWait:^{
    
        NSMutableArray<NSString *> *rejectedAuthIDs = [NSMutableArray array];
        
        // If an authorization has not been rejected, it is expected
        // for activeAuthorizationIds array to contain it's ID.
        for (Authorization *auth in [selectedAuthorizations allValues]) {
            if ([activeAuthorizationIds containsObject:auth.ID] == FALSE) {
                [rejectedAuthIDs addObject:auth.ID];
                // Authorization is removed from selectedAuthorizations dictionary.
                // This ensures the next call to -getNewAuthorizations does not return
                // any results.
                selectedAuthorizations[auth.accessType] = nil;
            }
        }
        
        if ([rejectedAuthIDs count] == 0) {
            return;
        }
        
        [PsiFeedbackLogger warnWithType:AuthorizationStoreLogType
                                 format:@"Rejected Authorization IDs: %@", rejectedAuthIDs];
        
        NSMutableArray<NSPredicate *> *sub = [NSMutableArray array];
        for (NSString *rejectedAuthID in rejectedAuthIDs) {
            [sub addObject:[NSPredicate predicateWithFormat:@"id == %@", rejectedAuthID]];
        }
        
        NSFetchRequest<SharedAuthorization *> *request = [SharedAuthorization fetchRequest];
        request.predicate = [NSCompoundPredicate orPredicateWithSubpredicates:sub];
        
        NSError *error = nil;
        NSArray<SharedAuthorization *> *fetchResult = [context executeFetchRequest:request
                                                                             error:&error];
        
        if (error != nil) {
            [PsiFeedbackLogger errorWithType:AuthorizationStoreLogType
                                     message:@"Failed to execute authorization fetch request"
                                      object:error];
            return;
        }
        
        // Sets value of "psiphondRejected" field to true.
        for (SharedAuthorization *obj in fetchResult) {
            obj.psiphondRejected = TRUE;
            if (obj.accessTypeValue == AuthorizationAccessTypeAppleSubscription ||
                obj.accessTypeValue == AuthorizationAccessTypeAppleSubscriptionTest) {
                subscriptionRejected = TRUE;
            }
        }
        
        // Saves any changes that have been made.
        if ([context hasChanges]) {
            [context save:&error];
            if (error != nil) {
                [PsiFeedbackLogger errorWithType:AuthorizationStoreLogType
                                         message:@"Failed to execute authorization deletions"
                                          object:error];
                return;
            }
        }
        
    }];
    
    return subscriptionRejected;
    
}

- (BOOL)hasActiveSubscriptionOrSpeedBoost {
    
    NSManagedObjectContext *context = [self getManagedObjectContext];

    if (context == nil) {
        return FALSE;
    }
    
    __block BOOL result = FALSE;
    
    [context performBlockAndWait:^{
        // Currently there are only Subscription and Speed Boost authorizations
        // so checking if selectedAuthorizations is empty is correct.
        result = [selectedAuthorizations count] != 0;
    }];
    
    return result;
    
}

- (BOOL)hasSubscriptionAuth {

    // Loads Core Data persistent container.
    NSManagedObjectContext *context = [self getManagedObjectContext];
    
    if (context == nil) {
        return FALSE;
    }
    
    __block BOOL result = FALSE;
    
    [context performBlockAndWait:^{
        
        NSFetchRequest<SharedAuthorization *> *request = [SharedAuthorization fetchRequest];
        request.predicate = [NSPredicate predicateWithFormat:
                             @"accessType == %@ AND psiphondRejected == 0", SubscriptionAccessType];
        
        NSError *error = nil;
        NSUInteger count = [context countForFetchRequest:request error:&error];
        
        if (error != nil) {
            [PsiFeedbackLogger errorWithType:AuthorizationStoreLogType
                                     message:@"Failed to execute subscription count request"
                                      object:error];
            result = FALSE;
            return;
        }
        
        result = count != 0;
        
    }];
    
    return result;
    
}

@end
