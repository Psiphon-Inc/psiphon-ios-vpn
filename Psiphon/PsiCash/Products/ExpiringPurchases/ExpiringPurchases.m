/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import "ExpiringPurchases.h"
#import "ExpiringPurchase.h"
#import "Logging.h"
#import "PsiCashErrorTypes.h"
#import "PsiFeedbackLogger.h"

@interface ExpiringPurchases ()
@property (strong, nonatomic, readwrite) RACReplaySubject<ExpiringPurchase*>* expiredPurchaseStream;
@end

@implementation ExpiringPurchases {
    NSString *userDefaultsDictionaryKey;
    NSMutableArray<ExpiringPurchase*> *internalRepresentation;
    RACReplaySubject<ExpiringPurchase*> *expiringPurchases;
    RACDisposable *disposable;
}

#pragma mark - Persistence

+ (NSString*)defaultUserDefaultsDictionaryKey {
    return @"kExpiringPurchasesDefaultDictionaryKey";
}

+ (ExpiringPurchases*)fromPersistedUserDefaults {
    NSString *key = [ExpiringPurchases defaultUserDefaultsDictionaryKey];
    return [ExpiringPurchases fromPersistedUserDefaultsWithKey:key];
}

+ (ExpiringPurchases*)fromPersistedUserDefaultsWithKey:(NSString*)key {
    ExpiringPurchases *instance = [[ExpiringPurchases alloc] init];
    instance->userDefaultsDictionaryKey = key;
    NSMutableArray<ExpiringPurchase*> *arrayFromUserDefaults = [self fromDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:key]];

    BOOL invalidEntries = FALSE;
    if (arrayFromUserDefaults != nil) {
        for (id obj in arrayFromUserDefaults) {
            if (![obj isKindOfClass:[ExpiringPurchase class]]) {
                invalidEntries = TRUE;
                break;
            } else {
                [instance->expiringPurchases sendNext:obj];
            }
        }
    }

    if (invalidEntries || arrayFromUserDefaults == nil) {
        instance->internalRepresentation = nil;
    } else {
        [ExpiringPurchases sortPurchasesByDate:arrayFromUserDefaults];
        instance->internalRepresentation = arrayFromUserDefaults;
    }

    return instance;
}

- (id)init {
    self = [super init];

    if (self) {
        expiringPurchases = [[RACReplaySubject alloc] init];
        self.expiredPurchaseStream = [[RACReplaySubject alloc] init];
        [self startListeningForExpiringPurchases];
    }

    return self;
}

- (void)dealloc {
    [disposable dispose];
}

- (BOOL)persistChangesToUserDefaults {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *dictionaryRepresentation = [self dictionaryRepresentation];
    [userDefaults setObject:dictionaryRepresentation forKey:userDefaultsDictionaryKey];
    return [userDefaults synchronize];
}

#pragma mark - Getters

- (NSArray<ExpiringPurchase*>*)allPurchases {
    return [self->internalRepresentation copy];
}

- (NSArray<ExpiringPurchase*>*)activePurchases {
    NSMutableArray<ExpiringPurchase*> *active = [[NSMutableArray alloc] init];
    NSDate *now = [NSDate date];
    for (ExpiringPurchase *purchase in self->internalRepresentation) {
        if ([purchase.expiryDate compare:now] == NSOrderedDescending) {
            [active addObject:purchase];
        }
    }
    return active;
}

- (NSArray<ExpiringPurchase*>*)expiredPurchases {
    NSMutableArray<ExpiringPurchase*> *expired = [[NSMutableArray alloc] init];
    NSDate *now = [NSDate date];
    for (ExpiringPurchase *purchase in self->internalRepresentation) {
        if ([purchase.expiryDate compare:now] != NSOrderedDescending) {
            [expired addObject:purchase];
        }
    }
    return expired;
}

#pragma mark - Mutations

+ (void)sortPurchasesByDate:(NSMutableArray<ExpiringPurchase*>*)purchases {
    [purchases sortUsingComparator:^NSComparisonResult(ExpiringPurchase  * _Nonnull p1, ExpiringPurchase  * _Nonnull p2) {
        return [p1.expiryDate compare:p2.expiryDate];
    }];
}

- (RACSignal<ExpiringPurchase*>*)expireSignalFromPurchase:(ExpiringPurchase*_Nonnull)purchase {
    return [RACSignal createSignal:^RACDisposable * _Nullable(id<RACSubscriber>  _Nonnull subscriber) {
        RACCompoundDisposable *compoundDisposable = [RACCompoundDisposable compoundDisposable];

        NSTimeInterval timeUntilExpiry = [purchase.expiryDate timeIntervalSinceDate:[NSDate date]];
        if (timeUntilExpiry > 0) {
            [PsiFeedbackLogger infoWithType:PsiCashLogType message:@"Expiring purchase with id %@ expires in %lf", purchase.authToken.ID, timeUntilExpiry];
            NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:timeUntilExpiry repeats:NO block:^(NSTimer *timer){
                if ([[NSDate date] compare:purchase.expiryDate] != NSOrderedAscending) {
                    [subscriber sendNext:purchase];
                    [subscriber sendCompleted];
                } else {
                    [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"Expiring purchase with id %@ has not yet expired, retrying...", purchase.authToken.ID];
                    [subscriber sendError:nil];
                }
            }];
            [compoundDisposable addDisposable:[RACDisposable disposableWithBlock:^{
                @autoreleasepool {
                    [timer invalidate];
                }
            }]];
        } else {
            [subscriber sendNext:purchase];
            [subscriber sendCompleted];
        }

        return compoundDisposable;
    }];
}

- (void)startListeningForExpiringPurchases {
    disposable = [[[expiringPurchases flattenMap:^__kindof RACSignal * _Nullable(ExpiringPurchase * _Nullable value) {
        return [self expireSignalFromPurchase:value];
    }] retry] subscribeNext:^(ExpiringPurchase *purchase) {
        [self.expiredPurchaseStream sendNext:purchase];
    } error:^(NSError * _Nullable error) {
        [disposable dispose];
    } completed:^{
        [disposable dispose];
    }];
}

- (ExpiringPurchase*)nextExpiringPurchase {
    if ([self->internalRepresentation count] > 0) {
        return [self->internalRepresentation objectAtIndex:0];
    }
    return nil;
}

- (void)addExpiringPurchase:(ExpiringPurchase*)purchase {
    NSUInteger index = [self->internalRepresentation indexOfObject:purchase
                                                        inSortedRange:NSMakeRange(0, [self->internalRepresentation count])
                                                              options:NSBinarySearchingInsertionIndex
                                                      usingComparator:^NSComparisonResult(ExpiringPurchase  * _Nonnull p1, ExpiringPurchase  * _Nonnull p2) {
                                                          return [p1.expiryDate compare:p2.expiryDate];
                                                      }];
    [self->internalRepresentation insertObject:purchase atIndex:index];
    [self persistChangesToUserDefaults];
    [expiringPurchases sendNext:purchase];
}

- (NSArray<ExpiringPurchase*>*)removeExpiredPurchases {
    NSArray<ExpiringPurchase*> *expired = [self expiredPurchases];
    [self->internalRepresentation removeObjectsInArray:expired];
    [self persistChangesToUserDefaults];
    return expired;
}

#pragma mark - Persistable protocol

+ (id)fromDictionary:(NSDictionary*)dictionary {
    NSArray<NSDictionary*> *arr = [dictionary objectForKey:@"purchases"];
    NSMutableArray<ExpiringPurchase*> *expiringPurchases = [[NSMutableArray alloc] init];
    for (NSDictionary *dictionary in arr) {
        ExpiringPurchase *ep = [ExpiringPurchase fromDictionary:dictionary];
        if (ep == nil) {
            [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"Failed to created expiring purchase from persisted dictionary %@. This purchase will be erased when purchases are next persisted.", dictionary];
        } else {
            [expiringPurchases addObject:ep];
        }
    }

    return expiringPurchases;
}

- (NSDictionary<NSString*, id<NSCopying, NSSecureCoding>>*)dictionaryRepresentation {
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    for (ExpiringPurchase *purchase in self->internalRepresentation) {
        [arr addObject:[purchase dictionaryRepresentation]];
    }
    return @{@"purchases": arr};
}

@end
