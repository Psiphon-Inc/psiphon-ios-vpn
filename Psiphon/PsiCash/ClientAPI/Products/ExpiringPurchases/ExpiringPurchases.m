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
#import "Logging.h"
#import "PsiCashErrorTypes.h"
#import "PsiFeedbackLogger.h"

@interface ExpiringPurchases ()
@property (strong, nonatomic, readwrite) RACReplaySubject<PsiCashPurchase*>* expiredPurchaseStream;
@end

@implementation ExpiringPurchases {
    NSString *userDefaultsDictionaryKey;
    NSMutableArray<PsiCashPurchase*> *internalRepresentation;
    RACReplaySubject<PsiCashPurchase*> *expiringPurchases;
    RACDisposable *disposable;
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

#pragma mark - Getters

- (NSArray<PsiCashPurchase*>*)allPurchases {
    return [self->internalRepresentation copy];
}

- (NSArray<PsiCashPurchase*>*)activePurchases {
    NSMutableArray<PsiCashPurchase*> *active = [[NSMutableArray alloc] init];
    NSDate *now = [NSDate date];
    for (PsiCashPurchase *purchase in self->internalRepresentation) {
        if ([purchase.expiry compare:now] == NSOrderedDescending) {
            [active addObject:purchase];
        }
    }
    return active;
}

- (NSArray<PsiCashPurchase*>*)expiredPurchases {
    NSMutableArray<PsiCashPurchase*> *expired = [[NSMutableArray alloc] init];
    NSDate *now = [NSDate date];
    for (PsiCashPurchase *purchase in self->internalRepresentation) {
        if ([purchase.expiry compare:now] != NSOrderedDescending) {
            [expired addObject:purchase];
        }
    }
    return expired;
}

#pragma mark - Mutations

+ (void)sortPurchasesByDate:(NSMutableArray<PsiCashPurchase*>*)purchases {
    [purchases sortUsingComparator:^NSComparisonResult(PsiCashPurchase  * _Nonnull p1, PsiCashPurchase  * _Nonnull p2) {
        return [p1.expiry compare:p2.expiry];
    }];
}

- (RACSignal<PsiCashPurchase*>*)expireSignalFromPurchase:(PsiCashPurchase*_Nonnull)purchase {
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> _Nonnull subscriber) {
        RACCompoundDisposable *compoundDisposable = [RACCompoundDisposable compoundDisposable];

        NSTimeInterval timeUntilExpiry = [purchase.expiry timeIntervalSinceDate:[NSDate date]];
        if (timeUntilExpiry > 0) {
            [PsiFeedbackLogger infoWithType:PsiCashLogType message:@"Expiring purchase with id %@ expires in %lf", purchase.authorization, timeUntilExpiry];
            NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:timeUntilExpiry repeats:NO block:^(NSTimer *timer){
                if ([[NSDate date] compare:purchase.expiry] != NSOrderedAscending) {
                    [subscriber sendNext:purchase];
                    [subscriber sendCompleted];
                } else {
                    [PsiFeedbackLogger errorWithType:PsiCashLogType message:@"Expiring purchase with id %@ has not yet expired, retrying...", purchase.authorization];
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
    disposable = [[[expiringPurchases flattenMap:^RACSignal *(PsiCashPurchase * _Nullable value) {
        return [self expireSignalFromPurchase:value];
      }]
      retry]
      subscribeNext:^(PsiCashPurchase *purchase) {
        [self.expiredPurchaseStream sendNext:purchase];
      }
      error:^(NSError * _Nullable error) {
        [disposable dispose];
      }
      completed:^{
        [disposable dispose];
      }];
}

- (void)addExpiringPurchase:(PsiCashPurchase*)purchase {
    NSUInteger index = [self->internalRepresentation indexOfObject:purchase
                                                        inSortedRange:NSMakeRange(0, [self->internalRepresentation count])
                                                              options:NSBinarySearchingInsertionIndex
                                                      usingComparator:^NSComparisonResult(PsiCashPurchase  * _Nonnull p1, PsiCashPurchase  * _Nonnull p2) {
                                                          return [p1.expiry compare:p2.expiry];
                                                      }];
    [self->internalRepresentation insertObject:purchase atIndex:index];
    [expiringPurchases sendNext:purchase];
}

- (void)addExpiringPurchases:(NSArray<PsiCashPurchase*>*)purchases {
    for (PsiCashPurchase* p in purchases) {
        [self addExpiringPurchase:p];
    }
}

- (NSArray<PsiCashPurchase*>*)removeExpiredPurchases {
    NSArray<PsiCashPurchase*> *expired = [self expiredPurchases];
    [self->internalRepresentation removeObjectsInArray:expired];
    return expired;
}

@end
