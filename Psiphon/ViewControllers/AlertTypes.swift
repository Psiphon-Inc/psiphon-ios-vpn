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

import PsiApi
import ReactiveSwift

typealias AlertEvent = Event<AlertType>

/// Represents (eventually all) alerts that are presented modally on top of view controllers.
/// Note: Alerts should not contains PII.
enum AlertType: Hashable {

    case psiCashAlert(PsiCashAlert)

    case psiCashAccountAlert(PsiCashAccountAlert)

    case disallowedTrafficAlert

    case genericOperationFailedTryAgain

    case error(localizedTitle: String, localizedMessage: String)
}

enum PsiCashAlert: Hashable {
    /// Presents an alert with a "Add PsiCash" button.
    case insufficientBalanceErrorAlert(localizedMessage: String)

}

enum PsiCashAccountAlert: Hashable {
    case loginSuccessLastTrackerMergeAlert
    case logoutSuccessAlert
    case incorrectUsernameOrPasswordAlert
    
    // Bad request response from PsiCash server.
    case accountLoginBadRequestAlert
    
    // Server error response from PsiCash server.
    case accountLoginServerErrorAlert
    
    case accountLoginCatastrophicFailureAlert
    
    case tunnelNotConnectedAlert
    
    case accountLogoutCatastrophicFailureAlert
    
    // PsiCash Account tokens expired
    case accountTokensExpiredAlert
}

enum DisallowedTrafficAlertAction: Equatable {
    case speedBoostTapped
    case subscriptionTapped
}

enum AlertAction: Equatable {

    /// "Dismissed" or "OK" button tapped.
    case dismissTapped

    case addPsiCashTapped


    case disallowedTrafficAlertAction(DisallowedTrafficAlertAction)
}

extension UIAlertController {

    /// - Parameter onActionButtonTapped: Call back for when one of the action buttons is tapped.
    /// The alert will have already been dismissed.
    static func makeUIAlertController(
        alertEvent: AlertEvent,
        onActionButtonTapped: @escaping (AlertEvent, AlertAction) -> Void
    ) -> UIAlertController {
        
        switch alertEvent.wrapped {
        case .psiCashAlert(let psiCashAlertType):
            switch psiCashAlertType {
            case .insufficientBalanceErrorAlert(let localizedMessage):
                return .makeAlert(
                    title: UserStrings.PsiCash(),
                    message: localizedMessage,
                    actions: [
                        .defaultButton(title: UserStrings.Add_psiCash()) {
                                onActionButtonTapped(alertEvent, .addPsiCashTapped)
                        },
                        .dismissButton {
                            onActionButtonTapped(alertEvent, .dismissTapped)
                        }
                    ]
                )
            }

        case .psiCashAccountAlert(let accountAlertType):
            switch accountAlertType {
            
            case .loginSuccessLastTrackerMergeAlert:
                return .makeAlert(
                    title: UserStrings.Psicash_login_success_title(),
                    message: UserStrings.Psicash_accounts_last_merge_warning_body(),
                    actions: [
                        .dismissButton {
                            onActionButtonTapped(alertEvent, .dismissTapped)
                        }
                    ])

            case .logoutSuccessAlert:
                return .makeAlert(
                    title: UserStrings.Psicash_account_logout_title(),
                    message: UserStrings.Psicash_account_logged_out_complete(),
                    actions: [
                        .dismissButton {
                            onActionButtonTapped(alertEvent, .dismissTapped)
                        }
                    ])

            case .incorrectUsernameOrPasswordAlert:
                return .makeAlert(
                    title: UserStrings.Psicash_login_failed_title(),
                    message: UserStrings.Incorrect_username_or_password(),
                    actions: [
                        .dismissButton {
                            onActionButtonTapped(alertEvent, .dismissTapped)
                        }
                    ])
                
            case .accountLoginBadRequestAlert:
                return .makeAlert(
                    title: UserStrings.Psicash_login_failed_title(),
                    message: UserStrings.Psicash_login_bad_request_error_body(),
                    actions: [
                        .dismissButton {
                            onActionButtonTapped(alertEvent, .dismissTapped)
                        }
                    ])

            case .accountLoginServerErrorAlert:
                return .makeAlert(
                    title: UserStrings.Psicash_login_failed_title(),
                    message: UserStrings.Psicash_login_server_error_body(),
                    actions: [
                        .dismissButton {
                            onActionButtonTapped(alertEvent, .dismissTapped)
                        }
                    ])
                
            case .accountLoginCatastrophicFailureAlert:
                return .makeAlert(
                    title: UserStrings.Psicash_login_failed_title(),
                    message: UserStrings.Psicash_login_catastrophic_error_body(),
                    actions: [
                        .dismissButton {
                            onActionButtonTapped(alertEvent, .dismissTapped)
                        }
                    ])
                
            case .tunnelNotConnectedAlert:
                return .makeAlert(
                    title: UserStrings.Psicash_account(),
                    message: UserStrings.In_order_to_use_PsiCash_you_must_be_connected(),
                    actions: [
                        .dismissButton {
                            onActionButtonTapped(alertEvent, .dismissTapped)
                        }
                    ])

            case .accountLogoutCatastrophicFailureAlert:
                return .makeAlert(
                    title: UserStrings.Psicash_account_logout_title(),
                    message: UserStrings.Psicash_account_logout_failed_body(),
                    actions: [
                        .dismissButton {
                            onActionButtonTapped(alertEvent, .dismissTapped)
                        }
                    ])
                
            case .accountTokensExpiredAlert:
                return .makeAlert(
                    title: UserStrings.Psicash_account(),
                    message: UserStrings.Psicash_account_tokens_expired_body(),
                    actions: [
                        .dismissButton {
                            onActionButtonTapped(alertEvent, .dismissTapped)
                        }
                    ])
            }

        case .disallowedTrafficAlert:
            return .makeAlert(
                title: UserStrings.Upgrade_psiphon(),
                message: UserStrings.Disallowed_traffic_alert_message(),
                actions: [
                    .defaultButton(title: UserStrings.Subscribe_action_button_title()) {
                        onActionButtonTapped(alertEvent,
                                             .disallowedTrafficAlertAction(.subscriptionTapped))
                    },
                    .defaultButton(title: UserStrings.Speed_boost()) {
                        onActionButtonTapped(alertEvent,
                                             .disallowedTrafficAlertAction(.speedBoostTapped))
                    },
                    .dismissButton {
                        onActionButtonTapped(alertEvent, .dismissTapped)
                    }
                ]
            )

        case .genericOperationFailedTryAgain:
            return .makeAlert(
                title: UserStrings.Error_title(),
                message: UserStrings.Operation_failed_please_try_again_alert_message(),
                actions: [
                    .dismissButton {
                        onActionButtonTapped(alertEvent, .dismissTapped)
                    }
                ])

        case .error(let localizedTitle, let localizedMessage):
            return .makeAlert(
                title: localizedTitle,
                message: localizedMessage,
                actions: [
                    .dismissButton {
                        onActionButtonTapped(alertEvent, .dismissTapped)
                    }
                ]
            )
        }
    }
    
}
