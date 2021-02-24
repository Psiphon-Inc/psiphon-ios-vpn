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

final class AdMobRewardedVideoAdController: StoreDelegate<AdAction> {
    
    typealias Status = AdControllerStatus<LoadError>
    
    /// Represents different failure types of AdMobRewardedVideoAdController ad controller.
    enum LoadError: HashableError {
        case deviceNotUntunneled
        case nilRewardData
        case adMobSDKError(SystemError<Int>)
    }
    
    private var status: Status = .noAdsLoaded {
        didSet {
            storeSend(.rewardedVideoAdUpdate(status, self))
        }
    }
    
    private var rewardedVideo: GADRewardedAd? = nil
    
    private let adUnitID: String
    
    init(adUnitID: String, store: Store<Utilities.Unit, AdAction>) {
        self.adUnitID = adUnitID
        super.init(store: store)
    }
    
    func load(rewardData: String?, adConsent: AdConsent) {
        
        guard let rewardData = rewardData else {
            self.status = .loadFailed(ErrorEvent(.nilRewardData, date: Date()))
            return
        }
        
        precondition(Thread.isMainThread, "load(request:) must be called on the main thread")
        
        self.status = .loading
        
        let request = adConsent.makeGADRequestWithNPA()
        
        GADRewardedAd.load(withAdUnitID: adUnitID, request: request) { maybeRewardedVideo, maybeError in
            
            precondition(Thread.isMainThread, "expected callback on main thread")
            
            if let error = maybeError {
                
                let adMobSDKError = SystemError<Int>.make(error as NSError)
                self.status = .loadFailed(
                    ErrorEvent(.adMobSDKError(adMobSDKError), date: Date()))
                
            } else  {
                
                guard let rewardedVideo = maybeRewardedVideo else {
                    fatalError()
                }
                
                self.rewardedVideo = rewardedVideo
                self.rewardedVideo?.fullScreenContentDelegate = self
                
                // Sets server-side custom string.
                let ssvOptions = GADServerSideVerificationOptions()
                ssvOptions.customRewardString = rewardData
                self.rewardedVideo!.serverSideVerificationOptions = ssvOptions
                
                self.status = .loadSucceeded(.notPresented)
                
            }
                        
        }
        
    }
    
    func present(fromRootViewController viewController: UIViewController) {
        
        precondition(Thread.isMainThread, "present(fromRootViewController:) must be called on the main thread")
        
        guard let rewardedVideo = self.rewardedVideo else {
            return
        }
                
        do {
            try rewardedVideo.canPresent(fromRootViewController: viewController)
        } catch {
            self.status = .loadSucceeded(.failedToPresent(.make(error as NSError)))
            return
        }
        
        rewardedVideo.present(fromRootViewController: viewController) { [unowned self] in
            self.storeSend(.rewardedVideoAdUserEarnedReward)
        }
        
    }
    
}

extension AdMobRewardedVideoAdController: GADFullScreenContentDelegate {
    
    func ad(
        _ ad: GADFullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        
        self.status = .loadSucceeded(.failedToPresent(SystemError<Int>.make(error as NSError)))
        
        // AdMob API or documentation does not specify all the reasons that
        // presentation of ad might fail.
        // For simplicity we will remove reference to current ad instance.
        self.rewardedVideo = nil
        
    }
    
    func adDidPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        self.status = .loadSucceeded(.presenting)
    }
    
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        self.status = .loadSucceeded(.dismissed)
        self.rewardedVideo = nil
    }
    
}
