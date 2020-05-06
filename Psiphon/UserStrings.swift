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

// Swift counterpart to ObjC `Strings.m`.
//
// Translation notes:
// - Ensure uniqueness of the localized string keys.
// - Windows client translations can be found here:
//   https://github.com/Psiphon-Inc/psiphon-windows/blob/master/src/webui/_locales/en/messages.json

@objc final class UserStrings: NSObject {

    @objc static func PsiCash() -> String {
        // PsiCash is not translated or transliterated.
        return "PsiCash"
    }

    static func PsiCash_balance() -> String {
        return NSLocalizedString("PSICASH_BALANCE", tableName: nil, bundle: Bundle.main,
                                 value: "PsiCash Balance:",
                                 comment: "PsiCash is a type of credit. Do not translate or transliterate 'PsiCash'. Text shown next to the user's PsiCash balance (a numerical value). Keep colon if appropriate.")
    }

    static func PsiCash_transaction_pending() -> String {
        return NSLocalizedString("PSICASH_TRANSACTION_PENDING", tableName: nil, bundle: Bundle.main,
                                 value: "Transaction Pending",
                                 comment: "An error that signifies a state where the user has made a 'PsiCash' purchase, but extra action is needed from the user to finish the transaction. Do not translate or transliterate 'PsiCash'.")
    }

    static func Connect_to_finish_psicash_transaction() -> String {
        return NSLocalizedString("CONNECT_TO_FINISH_PSICASH_TRANSACTION", tableName: nil, bundle: Bundle.main,
                                 value: "Please connect to Psiphon to finish your transaction",
                                 comment: "Text shown to the user telling them to connect to 'Psiphon', to finish their unfinished transaction. Do not translate or transliterate 'Psiphon'.")
    }
    
    static func PsiCash_wait_for_transaction_to_be_verified() -> String {
        return NSLocalizedString("PSICASH_WAIT_TRANSACTION_VERIFIED", tableName: nil, bundle: Bundle.main,
                                 value: "Please wait while your transaction is being verified",
                                 comment: "Message when the user has made a purchase, and paid successfully, however the transaction is not complete yet and is pending verification")
    }

    static func PsiCash_balance_out_of_date() -> String {
        return NSLocalizedString("PSICASH_BALANCE_OUT_OF_DATE_ALERT_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "PsiCash Balance Out of Date",
                                 comment: "User's PsiCash balance is not up to date. PsiCash is a type of credit. Do not translate or transliterate 'PsiCash'. Text is shown on an alert pop up title")
    }

    static func Connect_to_psiphon_to_update_psiCash() -> String {
        return NSLocalizedString("PSICASH_BALANCE_OUT_OF_DATE_ALERT_BODY", tableName: nil, bundle: Bundle.main,
                                 value: "Connect to Psiphon to update your PsiCash balance.",
                                 comment: "User's PsiCash balance is not up to date. PsiCash is a type of credit. Do not translate or transliterate 'Psiphon'. Do not translate or transliterate 'PsiCash'. Text is shown on an alert pop up title")
    }

    static func PsiCash_unavailable() -> String {
        return NSLocalizedString("PSICASH_UNAVAILABLE", tableName: nil, bundle: Bundle.main,
                                 value: "PsiCash Unavailable",
                                 comment: "PsiCash currently unavailable. PsiCash is a type of credit. Do not translate or transliterate 'PsiCash'.")
    }

    static func Purchasing_psiCash() -> String {
        return NSLocalizedString("PURCHASING_PSICASH", tableName: nil, bundle: Bundle.main,
                                 value: "Purchasing PsiCash…",
                                 comment: "Shown when the user is purchasing PsiCash. PsiCash is a type of credit. Do not translate or transliterate 'PsiCash'. Including ellipses '…' if appropriate.")
    }

    static func Purchasing_speed_boost() -> String {
        return NSLocalizedString("PURCHASING_SPEED_BOOST", tableName: nil, bundle: Bundle.main,
                                 value: "Purchasing Speed Boost…",
                                 comment: "Purchasing 'Speed Boost' product. Including ellipses '…' if appropriate. Do not transliterate 'Speed Boost'. 'Speed Boost' is a product that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.")
    }

    static func Speed_boost_active() -> String {
        return NSLocalizedString("SPEED_BOOST_ACTIVE", tableName: nil, bundle: Bundle.main,
                                 value: "Speed Boost Active",
                                 comment: "Do not transliterate 'Speed Boost'. 'Speed Boost' is a product that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.")
    }

    static func Speed_boost_you_already_have() -> String {
        return NSLocalizedString("SPEED_BOOST_YOU_ALREADY_HAVE", tableName: nil, bundle: Bundle.main,
                                 value: "You already have Speed Boost",
                                 comment: "Do not transliterate 'Speed Boost'. 'Speed Boost' is a product that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.")
    }

    static func Speed_boost_active(time: String) -> String {
        let format = NSLocalizedString("SPEED_BOOST_IS_ACTIVE", tableName: nil, bundle: Bundle.main,
                                       value: "Speed Boost Active %@",
                                       comment: "'%@' is going to be replace by a timer (e.g. '02:12'). Place the exact string '%@' at the appropriate place. This string is shown when the user's 'Speed Boost' is active. Do not transliterate 'Speed Boost'. 'Speed Boost' is a product that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.")
        return String(format: format, time)
    }

    static func Add_psiCash() -> String {
        return NSLocalizedString("ADD_PSICASH", tableName: nil, bundle: Bundle.main,
                                 value: "Add PsiCash",
                                 comment: "Button title to add to user's PsiCash balance. PsiCash is a type of credit. Do not translate or transliterate 'PsiCash'.")
    }

    static func Speed_boost() -> String {
        return NSLocalizedString("SPEED_BOOST", tableName: nil, bundle: Bundle.main,
                                 value: "Speed Boost",
                                 comment: "Do not transliterate 'Speed Boost'. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.")
    }

    static func Speed_boost_unavailable() -> String {
        return NSLocalizedString("SPEED_BOOST_UNAVAILABLE", tableName: nil, bundle: Bundle.main,
                                 value: "Speed Boost Unavailable",
                                 comment: "'Speed Boost' product is currently unavailable. Do not transliterate 'Speed Boost'. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.")
    }

    static func Connect_to_psiphon_to_use_speed_boost() -> String {
        return NSLocalizedString("CONNECT_TO_USE_SPEED_BOOST", tableName: nil, bundle: Bundle.main,
                                 value: "Connect to Psiphon to use Speed Boost",
                                 comment: "User must connect to 'Psiphon' in order to use 'Speed Boost' product. Do not translate or transliterate 'Psiphon'. Do not transliterate 'Speed Boost'. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.")
    }

    static func Insufficient_psiCash_balance() -> String {
        return NSLocalizedString("INSUFFICIENT_PSICASH_BALANCE", tableName: nil, bundle: Bundle.main,
                                 value: "Insufficient PsiCash balance",
                                 comment: "User does not have sufficient 'PsiCash' balance. PsiCash is a type of credit. Do not translate or transliterate 'PsiCash'.")

    }

    static func PsiCash_is_unavailable_while_subscribed() -> String {
        return NSLocalizedString("PSICASH_UNAVAILABLE_WHILE_SUBSCRIBED", tableName: nil, bundle: Bundle.main,
                                 value: "PsiCash is unavailable while subscribed",
                                 comment: "'PsiCash' features are unavailable while the user has a subscription. Do not translate or transliterate 'PsiCash'")
    }

    static func PsiCash_is_unavailable_while_connecting_to_psiphon() -> String {
        return NSLocalizedString("PSICASH_UNAVAILABLE_WHILE_CONNECTING", tableName: nil, bundle: Bundle.main,
                                 value: "PsiCash is unavailable while connecting to Psiphon",
                                 comment: "'PsiCash' features are unavailable while the app the connecting to 'Psiphon'. PsiCash is a type of credit. Do not translate or transliterate 'Psiphon'. Do not translate or transliterate 'PsiCash'")
    }
    
    static func PsiCash_purchase_notice() -> String {
        return NSLocalizedString("PSICASH_PURCHASE_SCREEN_NOTICE", tableName: nil, bundle: Bundle.main,
                                 value: "IMPORTANT: Your PsiCash will not be preserved if you uninstall Psiphon.",
                                 comment: "PsiCash in-app purchase disclaimer that appears on the bottom of the screen where users can buy different amounts of PsiCash from the PlayStore.  Do not translate or transliterate terms PsiCash")
    }

    static func Connect_to_psiphon_button() -> String {
        return NSLocalizedString("CONNECT_TO_PSIPHON", tableName: nil, bundle: Bundle.main,
                                 value: "Connect to Psiphon",
                                 comment: "Button title that lets the user to connect to the Psiphon network. Do not translate or transliterate 'Psiphon'")
    }

    static func Psiphon_is_not_connected() -> String {
        return NSLocalizedString("PSIPHON_IS_NOT_CONNECTED", tableName: nil, bundle: Bundle.main,
                                 value: "Psiphon is not connected",
                                 comment: "Shown when user is not connected to Psiphon network. Do not translate or transliterate 'Psiphon'")
    }

    static func Free() -> String {
        return NSLocalizedString("FREE_PSICASH_COIN", tableName: nil, bundle: Bundle.main,
                                 value: "Free",
                                 comment: "Button title for a product that is free. There is no cost or payment associated.")
    }
    
    static func Failed_to_load() -> String {
        return NSLocalizedString("FAILED_TO_LOAD", tableName: nil, bundle: Bundle.main,
                                 value: "Failed to load",
                                 comment: "Message shown when something fails to load")
    }
    
    static func Product_list_could_not_be_retrieved() -> String {
        return NSLocalizedString("PRODUCT_LIST_COULD_NOT_BE_RETRIEVED", tableName: nil, bundle: Bundle.main,
                                 value: "Product list could not be retrieved",
                                 comment: "Message shown when products available for purchase could not be retrieved.")

    }
    
    static func Tap_to_retry() -> String {
        return NSLocalizedString("TAP_TO_RETRY", tableName: nil, bundle: Bundle.main,
                                 value: "Tap to Retry",
                                 comment: "Button title shown when something fails to load. Asks the user to tap the button to retry the operation")
    }
}

// MARK: Internet reachability
extension UserStrings{
    static func No_internet_connection() -> String {
        return NSLocalizedString("NO_INTERNET_CONNECTION_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "No internet connection",
                                 comment: "Message shown to the user when there is no internet connect.")
    }
}

// MARK: Rewarded Videos
extension UserStrings {
    static func Watch_rewarded_video_and_earn() -> String {
        return NSLocalizedString("WATCH_REWARDED_VIDEO_AND_EARN", tableName: nil, bundle: Bundle.main,
                                 value: "Watch Video and Earn",
                                 comment: "Button subtitle informing the user that if pressed a rewarded video ad will be displayed and they will earn credit.")
    }

    static func Rewarded_video_load_failed() -> String {
        return NSLocalizedString("REWARDED_VIDEO_LOAD_FAILED", tableName: nil, bundle: Bundle.main,
                                 value: "Failed to load rewarded video. Please try again later.",
                                 comment: "Shown in a pop-up alert if user's rewarded video ad failed to load.")
    }
}

// MARK: General Strings
extension UserStrings {
    @objc static func Operation_failed_alert_message() -> String {
        return NSLocalizedString("ALERT_BODY_OPERATION_FAILED", tableName: nil, bundle: Bundle.main,
                                 value: "Operation failed, please try again.",
                                 comment: "Alert dialog body when requested operation by the user failed.")
    }

    static func Please_try_again_later() -> String {
        return NSLocalizedString("PLEASE_TRY_AGAIN_LATER", tableName: nil, bundle: Bundle.main,
                                 value: "Please try again later.",
                                 comment: "Subtitle shown when the current operation failed, asking the user to try again at a later time.")
    }

    static func Purchase_failed() -> String {
        return NSLocalizedString("GENERIC_PURCHASE_FAILED", tableName: nil, bundle: Bundle.main,
                                 value: "Purchase Failed",
                                 comment: "Generic alert shown when purchase of a product fails.")
    }
}

// MARK: Generic values
extension UserStrings {

    @objc static func Error_title() -> String {
            return  NSLocalizedString("ERROR_TITLE", tableName: nil, bundle: Bundle.main,
                                      value: "Error",
                                      comment: "Error alert title")
    }

    @objc static func Accept_button_title() -> String {
        return  NSLocalizedString("ACCEPT_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                  value: "Accept",
                                  comment: "Accept button title")
    }

    @objc static func Decline_button_title() -> String {
        return  NSLocalizedString("DECLINE_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                  value: "Decline",
                                  comment: "Decline button title")
    }

    @objc static func OK_button_title() -> String {
        return NSLocalizedString("OK_BUTTON", tableName: nil, bundle: Bundle.main,
                                 value: "OK",
                                 comment: "Alert OK Button")
    }

    @objc static func Dismiss_button_title() -> String {
        return NSLocalizedString("DISMISS_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Dismiss",
                                 comment: "Dismiss button title. Dismisses pop-up alert when the user clicks on the button")
    }

    @objc static func Cancel_button_title() -> String {
        return  NSLocalizedString("CANCEL_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                  value: "Cancel",
                                  comment: "Title for a button that cancels an action. This should be generic enough to make sense whenever a cancel button is used.")
    }

    @objc static func Done_button_title() -> String {
        return NSLocalizedString("DONE_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Done",
                                 comment: "Title of the button that dismisses a screen or a dialog")
    }
}

// MARK: VPN strings
extension UserStrings {
    
    @objc static func No_internet_alert_title() -> String {
        return NSLocalizedString("NO_INTERNET", tableName: nil, bundle: Bundle.main,
                                 value: "No Internet Connection",
                                 comment: "Alert title informing user there is no internet connection")
    }
    
    @objc static func No_internet_alert_body() -> String {
        return NSLocalizedString("TURN_ON_DATE", tableName: nil, bundle: Bundle.main,
                                 value: "Please turn on cellular data or use Wi-Fi.",
                                 comment: "Alert message informing user to turn on their cellular data or wifi to connect to the internet")
    }
    
    @objc static func Unable_to_start_alert_title() -> String {
        return NSLocalizedString("VPN_START_FAIL_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Unable to start",
                                 comment: "Alert dialog title indicating to the user that Psiphon was unable to start")
    }
    
    @objc static func Error_while_start_psiphon_alert_body() -> String {
        return NSLocalizedString("VPN_START_FAIL_MESSAGE", tableName: nil, bundle: Bundle.main,
                                 value: "An error occurred while starting Psiphon. Please try again.",
                                 comment: "Alert dialog message informing the user that an error occurred while starting Psiphon (Do not translate 'Psiphon'). The user should try again, and if the problem persists, they should try reinstalling the app.")
    }
    
    @objc static func Reinstall_vpn_config() -> String {
        return NSLocalizedString("SETTINGS_REINSTALL_VPN_CONFIGURATION_CELL_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Reinstall VPN profile",
                                 comment: "Title of cell in settings menu which, when pressed, reinstalls the user's VPN profile for Psiphon")
    }
    
    @objc static func Tunnel_provider_sync_failed_reinstall_config() -> String {
        return NSLocalizedString("VPN_SYNC_FAILED_REINSTALL_CONFIG", tableName: nil, bundle: Bundle.main,
                                 value: "If this error persists, please try 'Reinstall VPN Profile'.",
                                 comment: "Error message when something was wrong with the VPN. Asks the user that if the error persists, try tapping the 'Reinstall VPN Profile' button in the settings menu. 'Reinstall VPN Profile' translation has key SETTINGS_REINSTALL_VPN_CONFIGURATION_CELL_TITLE")
    }
    
    @objc static func Vpn_status_disconnected() -> String {
        return NSLocalizedString("VPN_STATUS_DISCONNECTED", tableName: nil, bundle: Bundle.main,
                                 value: "Disconnected",
                                 comment: "Status when the VPN is not connected to a Psiphon server, not trying to connect, and not in an error state")
    }

    @objc static func Vpn_status_invalid() -> String {
        return NSLocalizedString("VPN_STATUS_INVALID", tableName: nil, bundle: Bundle.main,
                                 value: "Disconnected",
                                 comment: "Status when the VPN is in an invalid state. For example, if the user doesn't give permission for the VPN configuration to be installed, and therefore the Psiphon VPN can't even try to connect.")
    }

    @objc static func Vpn_status_connected() -> String {
        return NSLocalizedString("VPN_STATUS_CONNECTED", tableName: nil, bundle: Bundle.main,
                                 value: "Connected",
                                 comment: "Status when the VPN is connected to a Psiphon server")
    }

    @objc static func Vpn_status_connecting() -> String {
        return NSLocalizedString("VPN_STATUS_CONNECTING", tableName: nil, bundle: Bundle.main,
                                 value: "Connecting",
                                 comment: "Status when the VPN is connecting; that is, trying to connect to a Psiphon server")
    }

    @objc static func Vpn_status_disconnecting() -> String {
        return NSLocalizedString("VPN_STATUS_DISCONNECTING", tableName: nil, bundle: Bundle.main,
                                 value: "Disconnecting",
                                 comment: "Status when the VPN is disconnecting. Sometimes going from connected to disconnected can take some time, and this is that state.")
    }

    @objc static func Vpn_status_reconnecting() -> String {
        return NSLocalizedString("VPN_STATUS_RECONNECTING", tableName: nil, bundle: Bundle.main,
                                 value: "Reconnecting",
                                 comment: "Status when the VPN was connected to a Psiphon server, got disconnected unexpectedly, and is currently trying to reconnect")
    }

    @objc static func Vpn_status_restarting() -> String {
        return NSLocalizedString("VPN_STATUS_RESTARTING", tableName: nil, bundle: Bundle.main,
                                 value: "Restarting",
                                 comment: "Status when the VPN is restarting.")
    }

}
