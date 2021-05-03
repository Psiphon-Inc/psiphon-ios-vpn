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
import GoogleMobileAds

final class AdMobInterstitialAdController: StoreDelegate<AdAction> {
    
    typealias Status = AdControllerStatus<LoadError>
    
    /// Represents different failure types of AdMobInterstitialAdController ad controller.
    enum LoadError: HashableError {
        case notUntunneled
        case adMobSDKError(SystemError<Int>)
    }
    
    private var status: Status = .noAdsLoaded {
        didSet {
            storeSend(.interstitialAdUpdate(status, self))
        }
    }
    
    private var interstitial: GADInterstitialAd? = nil
    
    private let adUnitID: String
    
    init(adUnitID: String, store: Store<Utilities.Unit, AdAction>) {
        self.adUnitID = adUnitID
        super.init(store: store)
    }
    
    func load() {
        
        precondition(Thread.isMainThread, "load(request:) must be called on the main thread")
        
        self.status = .loading
        
        let request = GADRequest.makeGADRequestWithNPA()
        
        GADInterstitialAd.load(withAdUnitID: adUnitID, request: request) { maybeInterstitial, maybeError in
            
            precondition(Thread.isMainThread, "expected callback on main thread")
            
            if let error = maybeError {
                
                let adMobSDKError = SystemError<Int>.make(error as NSError)
                self.status = .loadFailed(
                    ErrorEvent(.adMobSDKError(adMobSDKError), date: Date()))
                
            } else  {
                
                guard let interstitial = maybeInterstitial else {
                    fatalError()
                }
                
                self.interstitial = interstitial
                self.interstitial?.fullScreenContentDelegate = self
                self.status = .loadSucceeded(.notPresented)
                
            }
                        
        }
        
    }
    
    /// Returns `.none` if full-screen ad can be presented, otherwise returns an error message.
    func present(fromRootViewController viewController: UIViewController) -> ErrorMessage? {
        
        precondition(Thread.isMainThread, "present(fromRootViewController:) must be called on the main thread")
        
        guard let interstitial = self.interstitial else {
            return ErrorMessage("no rewarded video loaded")
        }
        
        guard !self.status.isPresentingAd else {
            return ErrorMessage("ad is already presenting")
        }
        
        // Checks if viewController passed in is being dismissed before
        // presenting the ad.
        // This check should be done regardless of the implementation details of the Ad SDK,
        // since in our experience that ad can fail to present due to this reason,
        // with no error reported back by the Ad SDK.
        guard !viewController.isBeingDismissed else {
            return ErrorMessage("presenting view controller being dismissed")
        }
                
        do {
            try interstitial.canPresent(fromRootViewController: viewController)
        } catch {
            // AdMob error value is not explained.
            // We will consider this presentation error as a fatal error.
            self.status = .loadSucceeded(.fatalPresentationError(.make(error as NSError)))
            return ErrorMessage("AdMob SDK cannot present interstitial ad")
        }
        
        // Ad is expected to be presented successfully.
        self.status = .loadSucceeded(.willPresent)
        
        interstitial.present(fromRootViewController: viewController)
        
        return .none
        
    }
    
}

extension AdMobInterstitialAdController: GADFullScreenContentDelegate {
    
    func ad(
        _ ad: GADFullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        
        self.status = .loadSucceeded(.fatalPresentationError(SystemError<Int>.make(error as NSError)))
        
        // AdMob API or documentation does not specify all the reasons that
        // presentation of ad might fail.
        // For simplicity we will remove reference to current ad instance.
        self.interstitial = nil
        
    }
    
    func adDidPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        self.status = .loadSucceeded(.didPresent)
    }
    
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        self.status = .loadSucceeded(.dismissed)
        self.interstitial = nil
    }
    
}
