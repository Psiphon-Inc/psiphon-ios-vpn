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
import UserMessagingPlatform
import PsiApi
import GoogleMobileAds

extension AdNetworkGeographicDebugging {
    
    var toUMPDebugGeography: UMPDebugGeography {
        // Direct mapping between PsiApi defined AdNetworkGeographicDebugging enum and
        // AdMob SDK UMPDebugGeography enum.
        switch self {
        case .disabled: return .disabled
        case .EEA: return .EEA
        case .notEEA: return .notEEA
        }
    }
    
}

extension UMPConsentType {
    
    var npaValue: String {
        switch self {
        case .nonPersonalized:
            return "1"
        case .personalized, .unknown:
            return "0"
        @unknown default:
            fatalError()
        }
    }
    
}

@objc final class AdConsent: NSObject {
    
    @objc static let sharedInstance = AdConsent()
    
    private var form: UMPConsentForm?
    
    /// This will determine whether or not user needs to provide consent.
    /// - Note: `consentInfoUpdate` should be called on every app launch.
    ///
    /// - Parameter completionHandler: Called after request for consent information update completes.
    /// If a consent form is available for downloading, it is called after the form is downloaded.
    @objc func consentInfoUpdate(completionHandler: @escaping (Error?) -> Void) {
        
        guard Thread.isMainThread else {
            fatalError()
        }
        
        let params = UMPRequestParameters()
        params.tagForUnderAgeOfConsent = false // false means users are not under age.
        
        if Debugging.adNetworkGeographicDebugging != .disabled {
            let debugSettings = UMPDebugSettings()
            debugSettings.testDeviceIdentifiers = adMobTestDeviceIdentifiers
            debugSettings.geography = Debugging.adNetworkGeographicDebugging.toUMPDebugGeography
            params.debugSettings = debugSettings
        }
        
        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: params) {
            if let error = $0 {
                completionHandler(error)
            } else {
                
                // The consent information state was updated. Form status can now be checked.
                let formStatus = UMPConsentInformation.sharedInstance.formStatus
                
                switch formStatus {
                case .available:
                    self.loadForm(completionHandler: completionHandler)
                    
                case .unavailable:
                    // Consent forms are unavailable. Showing a consent form is not required.
                    //
                    // There are a variety of reasons why a form may not be available, such as:
                    // - The user has limit ad tracking enabled.
                    // - User is tagged as under age of consent.
                    completionHandler(nil)
                    
                case .unknown:
                    // This should never happen after a call to requestConsentInfoUpdate.
                    completionHandler(ErrorRepr(repr: "ad consent form status is 'unknown'"))
                    
                @unknown default:
                    fatalError()
                }

            }
        }
        
    }
    
    /// Must be called on the main queue.
    fileprivate func loadForm(completionHandler: @escaping (Error?) -> Void) {
        
        guard Thread.isMainThread else {
            fatalError()
        }
        
        // Must be called on the main queue.
        UMPConsentForm.load { maybeForm, maybeError in
            if let error = maybeError {
                completionHandler(error)
            } else {
                // Holds a reference to the form for later use.
                self.form = maybeForm
                completionHandler(nil)
            }
        }
    }
    
    /// Presents any previously downloaded consent form if the consent status indicates that it is required.
    /// Should be called after `consentInfoUpdate(completionHandler:)` completes with no errors.
    /// - Note: Must be called on the main queue.
    /// - Parameter presentingViewController: Called when presenting consent form to get the top view controller.
    /// - Parameter completionHandler: Called after consent is collected, or called immediately if consent is already
    /// obtained or not required.
    @objc func presentConsentFormIfNeeded(
        fromViewController presentingViewController: @escaping () -> UIViewController,
        completionHandler: @escaping (Error?, UMPConsentStatus) -> Void
    ) {
        
        guard Thread.isMainThread else {
            fatalError()
        }
        
        // Determines whether the user requires consent.
        let consentStatus = UMPConsentInformation.sharedInstance.consentStatus
        switch consentStatus {
        case .required:
            guard let form = self.form else {
                completionHandler(ErrorRepr(repr: "consent form not loaded"), consentStatus)
                return
            }
            
            form.present(from: presentingViewController()) { [unowned self] maybeDismissError in
                // Closure called on the main queue.
                
                if let dismissError = maybeDismissError {
                    completionHandler(dismissError, consentStatus)
                } else {
                    self.form = nil
                    completionHandler(nil, consentStatus)
                }
            }
            
        case .notRequired, .obtained:
            completionHandler(nil, consentStatus)
            
        case .unknown:
            completionHandler(ErrorRepr(repr: "consent status is unknown"), consentStatus)
            
        @unknown default:
            fatalError()
        }
    }
    
    @objc func resetConsent() {
        // Should be called if UMP SDK is to be completed removed from the project.
        UMPConsentInformation.sharedInstance.reset()
    }
    
    @objc func makeGADRequestWithNPA() -> GADRequest {
        if #available(iOS 14.0, *) {
            let request = GADRequest()
            return request
        } else {
            let request = GADRequest()
            let extras = GADExtras()
            extras.additionalParameters =
                ["npa": UMPConsentInformation.sharedInstance.consentType.npaValue]
            request.register(extras)
            return request
        }
    }
    
}
