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
import ReactiveSwift

typealias PsiCashRefreshResult = PendingResult<PsiCashLibData, ErrorEvent<PsiCashRefreshError>>

struct PsiCashEffect {
    
    private let psiCash: PsiCash
    
    init(psiCash: PsiCash) {
        self.psiCash = psiCash
    }
    
    var libData: PsiCashLibData {
        self.psiCash.dataModel()
    }
    
    func refreshState(
        andGetPricesFor priceClasses: [PsiCashTransactionClass]
    ) -> Effect<PsiCashRefreshResult> {
        
        Effect { observer, lifetime in
            guard Current.tunneled else {
                observer.fulfill(value: .completed(.failure(ErrorEvent(.tunnelNotConnected))))
                return
            }
            
            observer.send(value: .pending)
            
            // Updates request metadata before sending the request.
            self.psiCash.setRequestMetadata()
            let purchaseClasses = priceClasses.map { $0.rawValue }
            
            self.psiCash.refreshState(purchaseClasses) { psiCashStatus, error in
                let result: Result<PsiCashLibData, ErrorEvent<PsiCashRefreshError>>
                switch (psiCashStatus, error) {
                case (.success, nil):
                    result = .success(self.psiCash.dataModel())
                case (.serverError, nil):
                    result = .failure(ErrorEvent(.serverError))
                case (.invalidTokens, nil):
                    result = .failure(ErrorEvent(.invalidTokens))
                case (_, .some(let error)):
                    result = .failure(ErrorEvent(.error(error as SystemError)))
                case (_, .none):
                    preconditionFailure("unknown PsiCash status '\(psiCashStatus)'")
                }
                
                observer.fulfill(value: .completed(result))
            }
        }
    }
    
    func purchaseProduct(_ purchasable: PsiCashPurchasableType) -> Effect<PsiCashPurchaseResult> {
        Effect { observer, lifetime in
            
            guard Current.tunneled else {
                observer.fulfill(value:
                    PsiCashPurchaseResult(
                        purchasable: purchasable,
                        refreshedLibData: self.psiCash.dataModel(),
                        result: .failure(ErrorEvent(.tunnelNotConnected)))
                )
                return
            }
            
            Current.psiCashLogger.logEvent("Purchase",
                                           withInfo: String(describing: purchasable),
                                           includingDiagnosticInfo: false)
            
            // Updates request metadata before sending the request.
            self.psiCash.setRequestMetadata()
            
            self.psiCash.newExpiringPurchaseTransaction(
                forClass: purchasable.rawTransactionClass,
                withDistinguisher: purchasable.distinguisher,
                withExpectedPrice: NSNumber(value: purchasable.price.inNanoPsi))
            { (status: PsiCashStatus, purchase: PsiCashPurchase?, error: Error?) in
                let result: PsiCashPurchaseResult
                if status == .success, let purchase = purchase {
                    result = PsiCashPurchaseResult(
                        purchasable: purchasable,
                        refreshedLibData: self.psiCash.dataModel(),
                        result: purchase.mapToPurchased().mapError {
                            ErrorEvent(PsiCashPurchaseResponseError.parseError($0))
                    })
                    
                } else {
                    result = PsiCashPurchaseResult(
                        purchasable: purchasable,
                        refreshedLibData: self.psiCash.dataModel(),
                        result: .failure(ErrorEvent(.serverError(status, error as SystemError?)))
                    )
                }
                
                observer.fulfill(value: result)
            }
        }
    }
    
    func modifyLandingPage(_ restrictedURL: RestrictedURL) -> Effect<RestrictedURL> {
        Effect {
            restrictedURL.map { url in
                var maybeModifiedURL: NSString?
                let error = self.psiCash.modifyLandingPage(url.absoluteString,
                                                           modifiedURL: &maybeModifiedURL)
                guard error == nil else {
                    Current.psiCashLogger.logErrorEvent("ModifyURLFailed",
                                                        withError: error,
                                                        includingDiagnosticInfo: true)
                    return url
                }
                
                guard let modifiedURL = maybeModifiedURL else {
                    Current.psiCashLogger.logErrorEvent("ModifyURLFailed",
                                                        withInfo: "modified URL is nil",
                                                        includingDiagnosticInfo: true)
                    return url
                }
                
                return URL(string: modifiedURL as String)!
            }
        }
    }
    
    func rewardedVideoCustomData() -> String? {
        var s: NSString?
        let error = psiCash.getRewardedActivityData(&s)
        
        guard error == nil else {
            Current.psiCashLogger.logErrorEvent("GetRewardedActivityDataFailed",
                                                withError: error,
                                                includingDiagnosticInfo: true)
            return nil
        }
        
        return s as String?
    }
    
    func expirePurchases() -> Effect<Never> {
        .fireAndForget {
            let sharedDBAuthIds = Current.sharedDB.getNonSubscriptionAuthorizations().map(\.id)
            self.psiCash.expirePurchases(notFoundIn: sharedDBAuthIds)
        }
    }
    
}
