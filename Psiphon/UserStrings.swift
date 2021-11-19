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
    
    @objc static func Psiphon() -> String {
        // Psiphon is not translated or transliterated.
        return "Psiphon"
    }
    
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
    
    static func PsiCash_speed_boost_product_not_found_update_app_message() -> String {
        return NSLocalizedString("PSICASH_SPEED_BOOST_PRODUCT_NOT_FOUND_MESSAGE", tableName: nil, bundle: Bundle.main,
                                 value: "Speed Boost product not found. Your app may be out of date. Please check for updates.",
                                 comment: "Alert error message informing user that their Speed Boost purchase request failed because they attempted to buy a product that is no longer available and that they should try updating or reinstalling the app. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.")
    }
    
    static func Insufficient_psiCash_balance() -> String {
        return NSLocalizedString("INSUFFICIENT_PSICASH_BALANCE", tableName: nil, bundle: Bundle.main,
                                 value: "Insufficient PsiCash balance",
                                 comment: "User does not have sufficient 'PsiCash' balance. PsiCash is a type of credit. Do not translate or transliterate 'PsiCash'.")
        
    }
    
    static func PsiCash_subscription_already_gives_premium_access_title() -> String {
        return NSLocalizedString("PSICASH_SUBSCRIPTION_PREMIUM_ACCESS_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Your Psiphon subscription gives you premium access!",
                                 comment: "A title message to the premium user (a user with a subscription when they are trying to navigate to PsiCash and Speed Boost screen. Do not translate or transliterate words PsiCash or Psiphon")
    }
    
    static func PsiCash_subscription_already_gives_premium_access_body() -> String {
        return NSLocalizedString("PSICASH_SUBSCRIPTION_PREMIUM_ACCESS_BODY", tableName: nil, bundle: Bundle.main,
                                 value: "Your Psiphon subscription already gives you always-on Speed Boost, so there is no reason to buy more. Your PsiCash balance will be retained should you ever decide to cancel your subscription.\n\nYou can still access your PsiCash account from the settings menu.",
                                 comment: "A description message to the premium user (a user with a subscription) when they are trying to navigate to PsiCash and Speed Boost screen. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed. Do not translate or transliterate words PsiCash or Psiphon")
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
    
    static func PsiCash_is_unavailable_while_disconnecting_from_psiphon() -> String {
        return NSLocalizedString("PSICASH_UNAVAILABLE_WHILE_DISCONNECTING", tableName: nil, bundle: Bundle.main,
                                 value: "PsiCash is unavailable while disconnecting from Psiphon",
                                 comment: "'PsiCash' features are unavailable while the app the is disconnecting from 'Psiphon'. PsiCash is a type of credit. Do not translate or transliterate 'Psiphon'. Do not translate or transliterate 'PsiCash'")
    }
    
    static func PsiCash_non_account_purchase_notice() -> String {
        return NSLocalizedString("PSICASH_NON_ACCOUNT_SCREEN_NOTICE", tableName: nil, bundle: Bundle.main,
                                 value: "IMPORTANT: Your PsiCash will not be preserved if you uninstall Psiphon, unless you have created a PsiCash account and are logged into your PsiCash account.",
                                 comment: "PsiCash in-app purchase disclaimer that appears on the bottom of the screen where users can buy different amounts of PsiCash from the PlayStore.  Do not translate or transliterate terms PsiCash")
    }
    
    static func Connect_to_psiphon_button() -> String {
        return NSLocalizedString("CONNECT_TO_PSIPHON", tableName: nil, bundle: Bundle.main,
                                 value: "Connect to Psiphon",
                                 comment: "Button title that lets the user to connect to the Psiphon network. Do not translate or transliterate 'Psiphon'")
    }
    
    static func Psiphon_connection_required() -> String {
        return NSLocalizedString("PSIPHON_CONNECTION_REQUIRED", tableName: nil, bundle: Bundle.main,
                                 value: "Psiphon Connection Required",
                                 comment: "Alert message informing user that a Psiphon connection is required")
    }
    
    static func In_order_to_use_PsiCash_you_must_be_connected() -> String {
        return NSLocalizedString("PSICASH_MUST_BE_CONNECTED", tableName: nil, bundle: Bundle.main,
                                 value: "In order to use PsiCash, you must be connected to the Psiphon network.",
                                 comment: "Body text of a modal dialog shown when the user tries to use (spend, buy, etc.) PsiCash, if they not currently connected. 'Use' here means buy, spend, or otherwise interact with. 'Psiphon' must not be translated/transliterated. 'PsiCash' must not be translated/transliterated.")
    }
    
    static func Psiphon_is_not_connected() -> String {
        return NSLocalizedString("PSIPHON_IS_NOT_CONNECTED", tableName: nil, bundle: Bundle.main,
                                 value: "Psiphon is not connected",
                                 comment: "Shown when user is not connected to Psiphon network. Do not translate or transliterate 'Psiphon'")
    }
    
    static func Connecting_to_psiphon() -> String {
        return NSLocalizedString("CONNECTING_TO_PSIPHON", tableName: nil, bundle: Bundle.main,
                                 value: "Connecting to Psiphon",
                                 comment: "Label text shown to user when the VPN is connecting to a Psiphon server. Do not translate or transliterate 'Psiphon'")
    }
    
    static func Free() -> String {
        return NSLocalizedString("FREE_PSICASH_COIN", tableName: nil, bundle: Bundle.main,
                                 value: "Free",
                                 comment: "Button title for a product that is free. There is no cost or payment associated.")
    }
    
    static func Loading_failed() -> String {
        return NSLocalizedString("LOADING_FAILED", tableName: nil, bundle: Bundle.main,
                                 value: "Loading failed",
                                 comment: "Message shown when a resource (online or offline) fails to load.")
    }
    
    static func Product_list_could_not_be_retrieved() -> String {
        return NSLocalizedString("PRODUCT_LIST_COULD_NOT_BE_RETRIEVED", tableName: nil, bundle: Bundle.main,
                                 value: "Product list could not be retrieved",
                                 comment: "Message shown when products available for purchase could not be retrieved.")
        
    }
    
    static func Failed_to_verify_psicash_purchase() -> String {
        return NSLocalizedString("FAILED_TO_VERIFY_PSICASH_IAP_PURCHASE", tableName: nil, bundle: Bundle.main,
                                 value: "Failed to verify purchase",
                                 comment: "Message shown when verification of a product already purchased fails.")
    }
    
    static func Tap_to_retry() -> String {
        return NSLocalizedString("TAP_TO_RETRY", tableName: nil, bundle: Bundle.main,
                                 value: "Tap to Retry",
                                 comment: "Button title shown when something fails to load. Asks the user to tap the button to retry the operation")
    }
    
    @objc static func Restore_purchases() -> String {
        return NSLocalizedString("RESTORE_PURCHASES", tableName: nil, bundle: Bundle.main,
                                 value: "Restore purchases",
                                 comment: "Button that restores users previous purchases")
    }
    
    @objc static func Purchases_restored_successfully() -> String {
        return NSLocalizedString("PURCHASES_RESTORED_SUCCESSFULLY", tableName: nil, bundle: Bundle.main,
                                 value: "Purchases restored successfully",
                                 comment: "Alert message that the users purchases have been restored successfully")
    }
    
    static func Onboarding_user_notification_permission_title() -> String {
        return NSLocalizedString("ONBOARDING_NOTIFICATION_PERMISSION_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Get notified about important network events",
                                 comment: "Onboarding screen title that will be asking the user permission to send notifications about important network events while they use the app.")
    }
    
    static func Onboarding_user_notification_permission_body() -> String {
        return NSLocalizedString("ONBOARDING_NOTIFICATION_PERMISSION_BODY", tableName: nil, bundle: Bundle.main,
                                 value: "Allow Psiphon to send notifications so that you can be notified of important network events.",
                                 comment: "Do not translate or transliterate 'Psiphon'. Onboarding screen asking user to give the Psiphon app permission to send notifications about important network events while they use the app.")
    }
    
    static func Select_language() -> String {
        return NSLocalizedString("SELECT_LANG", tableName: nil, bundle: Bundle.main,
                                 value: "SELECT LANGUAGE",
                                 comment: "Title for screen that allows user to select language. Use all capital letters in the translation only if it makes sense.")
    }
    
    @objc static func PsiCash_account_management() -> String {
        return NSLocalizedString("PSICASH_ACCOUNT_MANAGEMENT_2", tableName: nil, bundle: Bundle.main,
                                 value: "Manage account",
                                 comment: "Button title that opens 'PsiCash' account management.")
    }
    
    @objc static func Are_you_sure_psicash_account_logout() -> String {
        return NSLocalizedString("PSICASH_ACCOUNT_LOGOUT_CHECK_PROMPT", tableName: nil, bundle: Bundle.main,
                                 value: "Are you sure you want to log out of your PsiCash account?",
                                 comment: "Do not translate or transliterate 'PsiCash'. Alert message asking user if they are sure they would like to logout of their PsiCash account")
    }
    
    @objc static func Log_Out() -> String {
        return NSLocalizedString("LOG_OUT_BUTTON_TITLE_2", tableName: nil, bundle: Bundle.main,
                                 value: "Log out",
                                 comment: "Title of the button that lets users log out of their account")
    }
    
    @objc static func Logout_anyway() -> String {
        return NSLocalizedString("LOG_OUT_ANY_WAY_BUTTON_TITLE_2", tableName: nil, bundle: .main,
                                 value: "Log out anyway",
                                 comment: "Button in the modal dialog shown to users when they attempt to log out of their PsiCash account with no active Psiphon tunnel. Clicking this button will cause a local-only logout to be performed.")
    }
    
    @objc static func Connect() -> String {
        NSLocalizedString("CONNECT_BUTTON", tableName: nil, bundle: .main,
                          value: "Connect",
                          comment: "Button text telling the user that if they click it, Psiphon will start trying to connect to the network. This is shown to the user while Psiphon is disconnected.")
    }
    
    static func Protect_your_purchases() -> String {
        return NSLocalizedString("PROTECT_YOUR_PURCHASES", tableName: nil, bundle: Bundle.main,
                                 value: "Protect Your Purchases",
                                 comment: "Text for a link displayed when the user does not have a PsiCash account. It encourages them to make one. The word 'PsiCash' must not be translated or transliterated.")
    }
    
    static func Log_in_or_sign_up() -> String {
        return NSLocalizedString("LOG_IN_OR_SIGN_UP", tableName: nil, bundle: Bundle.main,
                                 value: "Log in or sign up",
                                 comment: "Message title informing the user that they must sign up for an account or log in to their account")
    }
    
    static func Sign_up_or_login_to_psicash_account_to_continue() -> String {
        return NSLocalizedString("LOG_IN_OR_SIGNUP_TO_CONTINUE", tableName: nil, bundle: Bundle.main,
                                 value: "Log in or create account to continue using PsiCash",
                                 comment: "Do not translate or transliterate 'PsiCash'. Informs the user that they must sign up for a PsiCash account or log in to their PsiCash account in order to user PsiCash features.")
    }
    
    static func Psicash_account() -> String {
        return NSLocalizedString("PSICASH_ACCOUNT", tableName: nil, bundle: Bundle.main,
                                 value: "PsiCash Account",
                                 comment: "Do not translate or transliterate 'PsiCash'. Header of a box providing context that the actions inside the box are related to PsiCash accounts.")
    }
    
    static func Psicash_accounts_last_merge_warning_body() -> String {
        return NSLocalizedString("PSICASH_ACCOUNTS_LAST_MERGE_WARNING_BODY", tableName: nil, bundle: Bundle.main,
                                 value: "You are logged into your PsiCash account. The preexisting balance from this device has been transferred into your account, but this is the last time a balance merge will occur.",
                                 comment: "Body text of a modal dialog shown when a PsiCash login succeeds. There is a fixed number of times that a user can merge a pre-account balance into a PsiCash account. This message indicates that the user has hit that limit and the merge that occurred is the last one allowed. The word 'PsiCash' must not be translated or transliterated.")
    }
    
    static func Incorrect_username_or_password() -> String {
        return NSLocalizedString("INCORRECT_USERNAME_OR_PASSWORD", tableName: nil, bundle: Bundle.main,
                                 value: "The username or password entered was incorrect.",
                                 comment: "Body text of a modal dialog shown when a PsiCash login fails due to bad username or password.")
    }
    
    static func Psicash_login_success_title() -> String {
        return NSLocalizedString("PSICASH_LOGIN_SUCCESS_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "PsiCash Login Success",
                                 comment: "Title of modal dialog shown when the PsiCash account login attempt succeeds, if additional information needs to be conveyed. The word 'PsiCash' must not be translated or transliterated.")
    }
    
    static func Psicash_login_failed_title() -> String {
        return NSLocalizedString("PSICASH_LOGIN_FAILED_TITLE", tableName: nil, bundle: .main,
                                 value: "PsiCash Login Failed",
                                 comment: "Title of modal dialog shown when the PsiCash account login attempt fails for some reason. Text within the modal will explain why. The word 'PsiCash' must not be translated or transliterated.")
    }
    
    @objc static func Psicash_account_logout_title() -> String {
        return NSLocalizedString("PSICASH_ACCOUNT_LOGOUT_TITLE", tableName: nil, bundle: .main,
                                 value: "PsiCash Account Logout",
                                 comment: "Header of a modal dialog that appears when the user tries to log out of their PsiCash account. The word 'PsiCash' must not be translated or transliterated.")
    }
    
    static func Psicash_account_logged_out_complete() -> String {
        return NSLocalizedString("PSICASH_ACCOUNT_LOGOUT_COMPLETE_TITLE", tableName: nil, bundle: .main,
                                 value: "PsiCash account logout complete.",
                                 comment: "An alert shown when the user logs out of their PsiCash account. The word 'PsiCash' must not be translated or transliterated.")
    }
    
    static func Psicash_account_logout_failed_body() -> String {
        return NSLocalizedString("PSICASH_ACCOUNT_LOGOUT_FAILED_BODY", tableName: nil, bundle: .main,
                                 value: "You logout attempt failed unexpectedly. Please try restarting the application.",
                                 comment: "Body of modal dialog shown when the user attempts to log out of their PsiCash account and an unexpected error occurs. Please don't modify the link URL.")
    }
    
    @objc static func PsiCash_logout_offline_body() -> String {
        return NSLocalizedString("PSICASH_LOGOUT_OFFLINE_BODY", tableName: nil, bundle: .main,
                                 value: "Being connected to the Psiphon network enables a more secure PsiCash logout. Would you like to connect before logging out?",
                                 comment: "Body of a modal dialog that appears when the user tries to log out of thier PsiCash account while not currently connected to the Psiphon network. We don't allow PsiCash network requests when not connected, so only an inferior localy-only logout is available. 'Psiphon' must not be translated/transliterated. The word 'PsiCash' must not be translated or transliterated.")
    }
    
    static func Psicash_login_bad_request_error_body() -> String {
        return NSLocalizedString("PSICASH_LOGIN_BAD_REQUEST_ERROR_BODY", tableName: nil, bundle: .main,
                                 value: "The PsiCash server indicated that the login request was invalid. Please try again later.",
                                 comment: "Body text of a modal dialog shown when a PsiCash account login fails due to a 'bad request' error. The word 'PsiCash' must not be translated or transliterated.")
    }
    
    static func Psicash_login_server_error_body() -> String {
        return NSLocalizedString("PSICASH_LOGIN_SERVER_ERROR_BODY", tableName: nil, bundle: .main,
                                 value: "The PsiCash server responded with an error while trying to log you in. Please try again later.",
                                 comment: "Body text of a modal dialog shown when a PsiCash account login fails due to a server error. The word 'PsiCash' must not be translated or transliterated.")
    }
    
    static func Psicash_login_catastrophic_error_body() -> String {
        return NSLocalizedString("PSICASH_LOGIN_CATASTROPHIC_ERROR_BODY", tableName: nil, bundle: .main,
                                 value: "Your PsiCash login attempt failed unexpectedly.",
                                 comment: "Body text of a modal dialog shown when a PsiCash login fails without a specific reason. The word 'PsiCash' must not be translated or transliterated.")
    }
    
    static func Psicash_account_tokens_expired_body() -> String {
        return NSLocalizedString("PSICASH_ACCOUNT_TOKENS_EXPIRED_BODY_2", tableName: nil, bundle: .main,
                                 value: "Your PsiCash login has expired. Please log back in.",
                                 comment: "An alert shown when the user's PsiCash account tokens expire. This is a normal occurrence (once per year), and the user needs to log into their PsiCash account again to continue to use it. The word 'PsiCash' must not be translated or transliterated.")
    }
    
    static func Encourage_psicash_account_creation_body() -> String {
        return NSLocalizedString("CREATE_PSICASH_ACCOUNT_BODY_2", tableName: nil, bundle: .main,
                                 value: "We strongly encourage you to make a PsiCash account before buying PsiCash. Having an account allows you to share your balance between devices and protect your purchases.\n\nIMPORTANT: Without an account your PsiCash will not be preserved if you uninstall Psiphon.",
                                 comment: "Body of a modal dialog that appears when the user tries to buy PsiCash with real money but doens't have an account. The word 'PsiCash' must not be translated or transliterated.")
    }
    
    static func Continue_without_account() -> String {
        return NSLocalizedString("CREATE_PSICASH_ACCOUNT_CONTINUE_BUTTON", tableName: nil, bundle: .main,
                                 value: "Continue without account",
                                 comment: "Button in the modal dialog encouraging users to create an account when they attempt to buy PsiCash with real money without one. If they click this button, they will continue on to the PsiCash store.")
    }
    
    static func Create_or_log_into_account() -> String {
        return NSLocalizedString("CREATE_PSICASH_ACCOUNT_CREATE_BUTTON", tableName: nil, bundle: .main,
                                 value: "Create or log into account",
                                 comment: "Button in the modal dialog encouraging users to create an account when they attempt to buy PsiCash with real money without one. If they click this button, they will be taken to a screen where they can create an account or log into an existing one.")
    }
    
    static func Loading() -> String {
        return NSLocalizedString("LOADING", tableName: nil, bundle: Bundle.main,
                                 value: "Loading...",
                                 comment: "Text displayed while app loads")
    }
    
    static func Speed_and_port_limits_header() -> String {
        return NSLocalizedString("PSICASH_SPEED_PORT_LIMITS_HEAD", tableName: nil, bundle: .main,
                                 value: "Speed and Port Limits",
                                 comment: "Heading for an information section explaining that there are port and speed restrictions when the user doesn't have Speed Boost active. Port here refers to port in computer networking.")
    }
    
    static func Speed_and_port_limits_body() -> String {
        return NSLocalizedString("PSICASH_SPEED_PORT_LIMITS_BODY", tableName: nil, bundle: .main,
                                 value: "Without active Speed Boost, your speed is limited and some internet traffic is not supported. Activate Speed Boost with PsiCash to unlock the full potential of your Psiphon experience.",
                                 comment: "Body of an information section explaining that there are port and speed restrictions when the user doesn't have Speed Boost active. The words 'PsiCash' and 'Psiphon' must not be translated or transliterated. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.")
    }
    
    static func Feedback_title() -> String {
        return NSLocalizedString("FEEDBACK_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Feedback",
                                 comment: "Title of screen that lets user to send feedback about the app to Psiphon Inc. Should be kept short.")
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
    
    static func Disconnect_from_psiphon_to_watch_and_earn_psicash() -> String {
        return NSLocalizedString("DISCONNECT_TO_WATCH_AND_EARN_PSICASH", tableName: nil, bundle: Bundle.main,
                                 value: "You must disconnect from Psiphon to watch a video to earn PsiCash",
                                 comment: "Text next to the button indicating to the user that the rewarded video advertisement is only available when they are not connected to Psiphon. Do not translate or transliterate 'PsiCash'. Do not translate or transliterate 'Psiphon'.")
    }
    
}

// MARK: General Strings
extension UserStrings {
    @objc static func Operation_failed_please_try_again_alert_message() -> String {
        return NSLocalizedString("ALERT_BODY_OPERATION_FAILED", tableName: nil, bundle: Bundle.main,
                                 value: "Operation failed, please try again.",
                                 comment: "Alert dialog body when requested operation by the user failed.")
    }
    
    static func Please_try_again_later() -> String {
        return NSLocalizedString("PLEASE_TRY_AGAIN_LATER", tableName: nil, bundle: Bundle.main,
                                 value: "Please try again later.",
                                 comment: "Subtitle shown when the current operation failed, asking the user to try again at a later time.")
    }
    
    static func PsiCash_lib_init_failed_send_feedback() -> String {
        return NSLocalizedString("PSICASH_LIB_INIT_FAILED_SEND_FEEDBACK", tableName: nil, bundle: Bundle.main,
                                 value: "PsiCash failed to load.\n\nIf this problem persists, please send a feedback.",
                                 comment: "Subtitle of an error message shown when the PsiCash feature is unavailable, asking the user to send us a feedback if this problem persists.")
    }
    
    static func Something_went_wrong_try_again_and_send_feedback() -> String {
        return NSLocalizedString("PLEASE_TRY_AGAIN_LATER_AND_SEND_FEEDBACK", tableName: nil, bundle: Bundle.main,
                                 value: "Something went wrong, please try again later.\n\nIf this problem persists, please send a feedback.",
                                 comment: "Subtitle of an error message shown when the current operation failed, asking the user to try again at a later time and send us a feedback if this problem persists.")
    }
    
    static func Purchase_failed() -> String {
        return NSLocalizedString("GENERIC_PURCHASE_FAILED", tableName: nil, bundle: Bundle.main,
                                 value: "Purchase Failed",
                                 comment: "Generic alert shown when purchase of a product fails.")
    }
    
    static func Create_account_button_title() -> String {
        return NSLocalizedString("CREATE_ACCOUNT_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Create account",
                                 comment: "Button label that lets users create a new account.")
    }
    
    static func Logging_in_ellipses() -> String {
        return NSLocalizedString("LOGGING_IN_ELLIPSES", tableName: nil, bundle: Bundle.main,
                                 value: "Logging in ...",
                                 comment: "Label indicating to the user that they are logging into their PsiCash account. Use ellipses if it makes sense.")
    }
    
    static func Logging_out_ellipses() -> String {
        return NSLocalizedString("LOGGING_OUT_ELLIPSES", tableName: nil, bundle: Bundle.main,
                                 value: "Logging out ...",
                                 comment: "Label indicating to the user that they are logging out of their PsiCash account. Use ellipses if it makes sense.")
    }
    
    @objc static func Log_in() -> String {
        return NSLocalizedString("LOG_IN_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Log in",
                                 comment: "Title on a button that lets users login to their account with the username and password they have entered.")
    }
    
    static func Username() -> String {
        return NSLocalizedString("USERNAME_TEXT_FIELD", tableName: nil, bundle: Bundle.main,
                                 value: "Username",
                                 comment: "Text field label where users can enter their account's username")
    }
    
    static func Password() -> String {
        return NSLocalizedString("PASSWORD_TEXT_FIELD", tableName: nil, bundle: Bundle.main,
                                 value: "Password",
                                 comment: "Text field label where users can enter their account's password")
    }
    
    static func Forgot_password_button_title() -> String {
        return NSLocalizedString("FORGOT_PASSWORD", tableName: nil, bundle: Bundle.main,
                                 value: "Forgot password?",
                                 comment: "Button title that lets users reset their password if they forgot their account's password.")
    }
    
    static func Forgot_username_or_password_button_title() -> String {
        return NSLocalizedString("FORGOT_USERNAME_OR_PASSWORD", tableName: nil, bundle: Bundle.main,
                                 value: "Forgot your password or username?",
                                 comment: "Button title that lets users reset their username or password if they forgot their account's username or password.")
    }
    
    static func Or() -> String {
        return NSLocalizedString("OR_SIGNUP_SIGNIN", tableName: nil, bundle: Bundle.main,
                                 value: "OR",
                                 comment: "Capitalize where it makes sense. Label visually separating Sign up section and sign in section of the app.")
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
    
    @objc static func Close_button_title() -> String {
        return  NSLocalizedString("CLOSE_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                  value: "Close",
                                  comment: "Title for a button that closes current screen.")
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

// MARK: Subscription-related Strings
extension UserStrings {
    
    @objc static func Subscription() -> String {
        NSLocalizedString(
            "SETTINGS_SUBSCRIPTION_ACTIVE", tableName: nil, bundle: .main,
            value: "Subscriptions",
            comment: "Subscriptions item title in the app settings when user has an active subscription. Clicking this item opens subscriptions view")
    }
    
    static func Subscription_bar_header() -> String {
        return NSLocalizedString(
            "SUBSCRIPTION_BAR_HEADER_TEXT_SUBSCRIBED", tableName: nil, bundle: .main,
            value: "SUBSCRIPTION",
            comment: "Header text beside button that opens paid subscriptions manager UI. At this point the user is subscribed. Please keep this text concise as the width of the text box is restricted in size.")
    }
    
    static func Subscription_pending_bar_header() -> String {
        return NSLocalizedString(
            "SUBSCRIPTION_BAR_HEADER_TEXT_SUBSCRIPTION_PENDING", tableName: nil, bundle: .main,
            value: "SUBSCRIPTION PENDING",
            comment: "After a user successfully purchases a subscription, it needs to be activated. This title is displayed on the main screen indicating that the subscription is pending activation.")
    }
    
    static func Premium_max_speed_footer_subscribed() -> String {
        return NSLocalizedString(
            "SUBSCRIPTION_BAR_FOOTER_TEXT_SUBSCRIBED_V2", tableName: nil, bundle: .main,
            value: "Premium • Max Speed",
            comment: "Footer text beside button that opens paid subscriptions manager UI. At this point the user is subscribed. If “Premium” doesn't easily translate, please choose a term that conveys “Pro” or “Extra” or “Better” or “Elite”. Please keep this text concise as the width of the text box is restricted in size.")
    }
    
    static func Get_premium_header_not_subscribed() -> String {
        return NSLocalizedString(
            "SUBSCRIPTION_BAR_HEADER_TEXT_NOT_SUBSCRIBED", tableName: nil, bundle: .main,
            value: "GET PREMIUM",
            comment: "Header text beside button that opens paid subscriptions manager UI. At this point the user is not subscribed. If “Premium” doesn't easily translate, please choose a term that conveys “Pro” or “Extra” or “Better” or “Elite”. Please keep this text concise as the width of the text box is restricted in size.")
    }
    
    static func Remove_ads_max_speed_footer_not_subscribed() -> String {
        return NSLocalizedString(
            "SUBSCRIPTION_BAR_FOOTER_TEXT_NOT_SUBSCRIBED_2", tableName: nil, bundle: .main,
            value: "Remove ads • Max speed",
            comment: "Footer text beside button that opens paid subscriptions manager UI. At this point the user is not subscribed. Please keep this text concise as the width of the text box is restricted in size.")
    }
    
    static func Connect_to_activate_subscription() -> String {
        return NSLocalizedString(
            "SUBSCRIPTION_CONNECT_TO_ACTIVATE", tableName: nil, bundle: .main,
            value: "Connect to activate",
            comment: "After a user successfully purchases a subscription, it needs to be activated. Label with this text displayed on the main screen, indicating that the user needs to connect to Psiphon in order to activate the subscription.")
    }
    
    static func Failed_to_activate_subscription() -> String {
        return NSLocalizedString(
            "SUBSCRIPTION_FAILED_TO_ACTIVATE", tableName: nil, bundle: .main,
            value: "Failed to activate",
            comment: "After a user successfully purchases a subscription, it needs to be activated. Label with this text is displayed on the main screen, indicating that activation of user's subscription failed.")
    }
    
    static func Please_wait_while_activating_subscription() -> String {
        return NSLocalizedString(
            "SUBSCRIPTION_PLEASE_WAIT_WHILE_ACTIVATING", tableName: nil, bundle: .main,
            value: "Please wait while activating",
            comment: "After a user successfully purchases a subscription, it needs to be activated. Label with this text is displayed on the main screen, indicating to the user that the subscription is in the process of getting activated")
    }
    
    static func Manage_subscription_button_title() -> String {
        return NSLocalizedString(
            "SUBSCRIPTIONS_MANAGE_SUBSCRIPTION_BUTTON", tableName: nil, bundle: .main,
            value: "Manage",
            comment: "Label on a button which, when pressed, opens a screen where the user can manage their currently active subscription.")
    }
    
    static func Subscribe_action_button_title() -> String {
        return NSLocalizedString(
            "SUBSCRIPTIONS_SUBSCRIBE_BUTTON", tableName: nil, bundle: .main,
            value: "Subscribe",
            comment: "Label on a button which, when pressed, opens a screen where the user can choose from multiple subscription plans.")
    }
    
    static func Activating_subscription_title() -> String {
        return NSLocalizedString(
            "ACTIVATE_SUBSCRIPTION_BUTTON_TITILE", tableName: nil, bundle: .main,
            value: "Activating…",
            comment: "After a user successfully purchases a subscription, it needs to be activated. A label with this title is presented to the user indicating the the subscription is in the process of getting activated. Include the ellipses or equivalent symbol if it makes sense in the translated language.")
    }
    
    static func Connect_button_title() -> String {
        return NSLocalizedString(
            "CONNECT_BUTTON_TITLE", tableName: nil, bundle: .main,
            value: "Connect",
            comment: "Action button title, that when pressed connects the user to Psiphon network.")
    }
    
    @objc static func Retry_button_title() -> String {
        return NSLocalizedString(
            "RETRY_BUTTON_TITLE", tableName: nil, bundle: .main,
            value: "Retry",
            comment: "Action button title, that when pressed retries the recently failed operation.")
    }
    
}

// MARK: Disallowed traffic
extension UserStrings {
    
    static func Upgrade_psiphon() -> String {
        return NSLocalizedString("UPGRADE_PSIPHON", tableName: nil, bundle: Bundle.main,
                                 value: "Upgrade Psiphon",
                                 comment: "Do not translate or transliterate 'Psiphon'. This is title of an alert which is shown to the user when Psiphon server detects an unsupported Internet traffic request.")
    }
    
    static func Disallowed_traffic_alert_message() -> String {
        return NSLocalizedString("DISALLOWED_TRAFFIC_ALERT_MESSAGE", tableName: nil, bundle: Bundle.main,
                                 value: "Some Internet traffic is not supported by the free version of Psiphon. Purchase a subscription or Speed Boost to unlock the full potential of your Psiphon experience.",
                                 comment: "Content of the alert dialog which is shown to the user when they click toolbar notification of unsupported Internet traffic request.")
    }
}

// MARK: Feedback
extension UserStrings {
    
    static func Serious_errror_occurred_error_title() -> String {
        return NSLocalizedString("SERIOUS_ERROR_OCCURRED", tableName: nil, bundle: Bundle.main,
                                 value: "A serious error occurred",
                                 comment: "Title of an error dialog shown to the user when a serious error occurs in the app")
    }
    
    static func Help_improve_psiphon_by_sending_report() -> String {
        return NSLocalizedString("HELP_IMPROVE_PSIPHON_BY_SENDING_REPORT", tableName: nil, bundle: Bundle.main,
                                 value: "Help improve Psiphon by sending a report of this error.",
                                 comment: "Body of an error dialog asking the user to send Psiphon a report. Do not translate or transliterate 'Psiphon'")
    }
    
    static func Report_button_title() -> String {
        return NSLocalizedString("REPORT_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Report...",
                                 comment: "Title of a button that enables the user to report an error that they faced to us.")
    }
    
    static func Submitted_feedback() -> String {
        return NSLocalizedString("FEEDBACK_UPLOAD_SUCCESSFUL_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Thank you for helping improve Psiphon!",
                                 comment: "Alert dialog message thanking the user for helping improve the Psiphon network by submitting their feedback.")
    }
    
}

// MARK: PsiCash product titles

extension UserStrings {
    
    static func Speed_boost_1_hour() -> String {
        return NSLocalizedString("SPEED_BOOST_1HR", tableName: nil, bundle: Bundle.main,
                                 value: "1 hour",
                                 comment: "Label on a button. Clicking this button will buy 1 hour of Speed Boost. Translate number as well.")
    }
    
    static func Speed_boost_2_hours() -> String {
        return NSLocalizedString("SPEED_BOOST_2HR", tableName: nil, bundle: Bundle.main,
                                 value: "2 hours",
                                 comment: "Label on a button. Clicking this button will buy 2 hours of Speed Boost. Translate number as well.")
    }
    
    static func Speed_boost_3_hours() -> String {
        return NSLocalizedString("SPEED_BOOST_3HR", tableName: nil, bundle: Bundle.main,
                                 value: "3 hours",
                                 comment: "Label on a button. Clicking this button will buy 3 hours of Speed Boost. Translate number as well.")
    }
    
    static func Speed_boost_4_hours() -> String {
        return NSLocalizedString("SPEED_BOOST_4HR", tableName: nil, bundle: Bundle.main,
                                 value: "4 hours",
                                 comment: "Label on a button. Clicking this button will buy 4 hours of Speed Boost. Translate number as well.")
    }
    
    static func Speed_boost_5_hours() -> String {
        return NSLocalizedString("SPEED_BOOST_5HR", tableName: nil, bundle: Bundle.main,
                                 value: "5 hours",
                                 comment: "Label on a button. Clicking this button will buy 5 hours of Speed Boost. Translate number as well.")
    }
    
    static func Speed_boost_6_hours() -> String {
        return NSLocalizedString("SPEED_BOOST_6HR", tableName: nil, bundle: Bundle.main,
                                 value: "6 hours",
                                 comment: "Label on a button. Clicking this button will buy 6 hours of Speed Boost. Translate number as well.")
    }
    
    static func Speed_boost_7_hours() -> String {
        return NSLocalizedString("SPEED_BOOST_7HR", tableName: nil, bundle: Bundle.main,
                                 value: "7 hours",
                                 comment: "Label on a button. Clicking this button will buy 7 hours of Speed Boost. Translate number as well.")
    }
    
    static func Speed_boost_8_hours() -> String {
        return NSLocalizedString("SPEED_BOOST_8HR", tableName: nil, bundle: Bundle.main,
                                 value: "8 hours",
                                 comment: "Label on a button. Clicking this button will buy 8 hours of Speed Boost. Translate number as well.")
    }
    
    static func Speed_boost_9_hours() -> String {
        return NSLocalizedString("SPEED_BOOST_9HR", tableName: nil, bundle: Bundle.main,
                                 value: "9 hours",
                                 comment: "Label on a button. Clicking this button will buy 9 hours of Speed Boost. Translate number as well.")
    }
    
}

// MARK: Privacy Policy

extension UserStrings {
    
    static func privacyPolicyHTMLText_v2021_10_06(languageCode: String) -> String {
        
        let privacy_information_collected_websites_google_analytics_para_1 = NSLocalizedString("privacy-information-collected-websites-google-analytics-para-1", tableName: nil, bundle: Bundle.main,
                                                                                               value: "We use Google Analytics on some of our websites to collect information about usage. The information collected by Google Analytics will only be used for statistical analysis related to your browsing behaviour on this specific site. The information we obtain from Google Analytics is not personally identifying, nor is it combined with information from other sources to create personally identifying information.",
                                                                                               comment: "")
        let privacy_information_collected_vpndata_whycare_para_2 = NSLocalizedString("privacy-information-collected-vpndata-whycare-para-2", tableName: nil, bundle: Bundle.main,
                                                                                     value: "When you use a VPN, all data to and from your device goes through it. If you visit a website that uses unencrypted HTTP, all of that site's data is visible to the VPN. If you visit a website that uses encrypted HTTPS, the site content is encrypted, but some information about the site might be visible to the VPN. Other apps and services on your device will also transfer data that is encrypted or unencrypted. (Note that this is distinct from the encryption that all VPNs provide. Here we're only concerned with data that is or is not encrypted <em>inside</em> the VPN tunnel.)",
                                                                                     comment: "Paragraph text in the 'Why should you care?' subsection of the 'User Activity and VPN Data' section of the Privacy page. '<em>' is an 'emphasis' (like italics) HTML tag, which can be used if it makes sense in your language.")
        let privacy_information_collected_vpndata_whopsiphonshareswith_para_2_item_2 = NSLocalizedString("privacy-information-collected-vpndata-whopsiphonshareswith-para-2-item-2", tableName: nil, bundle: Bundle.main,
                                                                                                         value: "The blocking patterns in a given country, for example during political events.",
                                                                                                         comment: "Bullet list text under 'Who does Psiphon share Aggregated Data with?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_aggdata_subhead = NSLocalizedString("privacy-information-collected-vpndata-aggdata-subhead", tableName: nil, bundle: Bundle.main,
                                                                                      value: "Aggregated Data",
                                                                                      comment: "Sub-heading for the definition of 'Aggregated Data' under the 'User Activity and VPN Data' section of the Privacy Policy page.")
        let privacy_information_collected_psicash_para_2b = NSLocalizedString("privacy-information-collected-psicash-para-2b", tableName: nil, bundle: Bundle.main,
                                                                              value: "Creating a PsiCash account is optional. If an account is created, account-specific information such as username, password, and email address (if provided) are stored on the server. When logged in to a Psiphon client, the username is also stored locally.",
                                                                              comment: "Paragraph text on the Privacy Policy page. Describes the user data requirements for PsiCash accounts. 'PsiCash' must not be translated or transliterated. 'Psiphon' must not be translated or transliterated.")
        let privacy_information_collected_vpndata_whatdoespsiphondowith_para_2_item_2 = NSLocalizedString("privacy-information-collected-vpndata-whatdoespsiphondowith-para-2-item-2", tableName: nil, bundle: Bundle.main,
                                                                                                          value: "Monitor threats to our users' devices: We watch for malware infections that attempt to contact command-and-control servers.",
                                                                                                          comment: "Bullet list text under 'What does Psiphon do with User Activity and Aggregated Data?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_whycare_subhead = NSLocalizedString("privacy-information-collected-vpndata-whycare-subhead", tableName: nil, bundle: Bundle.main,
                                                                                      value: "Why should you care?",
                                                                                      comment: "Sub-heading in the 'User Activity and VPN Data' section of the Privacy Policy page. The section describes why it's important for users to consider what a VPN does with their traffic data.")
        let privacy_information_collected_psicash_para_4_item_3 = NSLocalizedString("privacy-information-collected-psicash-para-4-item-3", tableName: nil, bundle: Bundle.main,
                                                                                    value: "user agent string",
                                                                                    comment: "Bullet list item in the 'operation of the system' list. This item refers to 'user agent string' of the client software used to perform an action. This can be either a web browser or the Psiphon client itself.")
        let privacy_information_collected_mypsicash_para_1 = NSLocalizedString("privacy-information-collected-mypsicash-para-1", tableName: nil, bundle: Bundle.main,
                                                                               value: "Users create and manage their PsiCash accounts on the <a href=\"https://my.psi.cash\" target=\"_blank\" rel=\"noopener noreferrer\">my.psi.cash</a> website.",
                                                                               comment: "Paragraph text in the 'my.psi.cash' section of the Privacy page. 'my.psi.cash' is the domain name of the website and must not be translated or transliterated. 'PsiCash' must not be translated or transliterated.")
        let privacy_information_collected_client_advertising_networks_para_1 = NSLocalizedString("privacy-information-collected-client-advertising-networks-para-1", tableName: nil, bundle: Bundle.main,
                                                                                                 value: "We sometimes use advertisements to support our service, which may use technology such as cookies and web beacons. Our advertising partners' use of cookies enable them and their partners to serve ads based on your usage data. Any information collected through this process is handled under the terms of our advertising partners' privacy policies:",
                                                                                                 comment: "")
        let privacy_information_collected_data_categories_header = NSLocalizedString("privacy-information-collected-data-categories-header", tableName: nil, bundle: Bundle.main,
                                                                                     value: "Data Categories",
                                                                                     comment: "Heading for a section in our privacy policy. Under this heading will be sections with the different categories of data covered by the privacy policy.")
        let privacy_information_collected_vpndata_whopsiphonshareswith_para_2_item_3 = NSLocalizedString("privacy-information-collected-vpndata-whopsiphonshareswith-para-2-item-3", tableName: nil, bundle: Bundle.main,
                                                                                                         value: "That the populace of a country is determined to access the open internet.",
                                                                                                         comment: "Bullet list text under 'Who does Psiphon share Aggregated Data with?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_kindsofdata_subhead = NSLocalizedString("privacy-information-collected-vpndata-kindsofdata-subhead", tableName: nil, bundle: Bundle.main,
                                                                                          value: "What kinds of user data does Psiphon collect?",
                                                                                          comment: "Sub-heading in the 'User Activity and VPN Data' section of the Privacy Policy page.")
        let privacy_information_collected_psicash_para_3_list_start = NSLocalizedString("privacy-information-collected-psicash-para-3-list-start", tableName: nil, bundle: Bundle.main,
                                                                                        value: "In the user's web browser, some data is stored to allow for earning rewards and making purchases. This data includes:",
                                                                                        comment: "Paragraph text in the 'PsiCash' section of the Privacy page. This is preamble to a detailed bullet list. 'PsiCash' must not be translated or transliterated.")
        let privacy_information_collected_psicash_para_2_item_1 = NSLocalizedString("privacy-information-collected-psicash-para-2-item-1", tableName: nil, bundle: Bundle.main,
                                                                                    value: "generated user access tokens",
                                                                                    comment: "Bullet list item in the 'operation of the system' list. This item refers to randomly generated values that allow a user to access and utilize the system.")
        let privacy_information_collected_vpndata_useractivity_subhead = NSLocalizedString("privacy-information-collected-vpndata-useractivity-subhead", tableName: nil, bundle: Bundle.main,
                                                                                           value: "User Activity Data",
                                                                                           comment: "Sub-heading for the definition of 'User Activity Data' under the 'User Activity and VPN Data' section of the Privacy Policy page.")
        let privacy_information_collected_vpndata_whopsiphonshareswith_para_1_v2 = NSLocalizedString("privacy-information-collected-vpndata-whopsiphonshareswith-para-1-v2", tableName: nil, bundle: Bundle.main,
                                                                                                     value: "Shareable aggregated data is shared with sponsors, organizations we collaborate with, and civil society researchers. The data can be used to show such things as:",
                                                                                                     comment: "Paragraph text in the 'Who does Psiphon share these statistics with?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_shareable_para_1 = NSLocalizedString("privacy-information-collected-vpndata-shareable-para-1", tableName: nil, bundle: Bundle.main,
                                                                                       value: "When sharing aggregated data with third parties, we make sure that the data could not be combined with other sources to reveal user identities. For example, we do not share data for countries that only have a few Psiphon users in a day. We make sure that the data is anonymized.",
                                                                                       comment: "Paragraph text in the 'Shareable Aggregated Data' definition subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_aggdata_para_2 = NSLocalizedString("privacy-information-collected-vpndata-aggdata-para-2", tableName: nil, bundle: Bundle.main,
                                                                                     value: "An example of aggregated data might be: On a particular day, 250 people connected from New York City using Comcast, and transferred 200GB from <code>youtube.com</code> and 500GB in total.",
                                                                                     comment: "Paragraph text in the 'Aggregated Data' definition subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let faq_information_collected_answer_para_8_list_start = NSLocalizedString("faq-information-collected-answer-para-8-list-start", tableName: nil, bundle: Bundle.main,
                                                                                   value: "Android:",
                                                                                   comment: "")
        let privacy_information_collected_vpndata_useractivity_para_3 = NSLocalizedString("privacy-information-collected-vpndata-useractivity-para-3", tableName: nil, bundle: Bundle.main,
                                                                                          value: "An example of user activity data might be: At a certain time a user connected from New York City, using Comcast, and transferred 100MB from <code>youtube.com</code> and 300MB in total.",
                                                                                          comment: "Paragraph text in the 'User Activity Data' definition subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let faq_information_collected_answer_para_8_item_2 = NSLocalizedString("faq-information-collected-answer-para-8-item-2", tableName: nil, bundle: Bundle.main,
                                                                               value: "Device model",
                                                                               comment: "")
        let privacy_information_collected_s3_logging_para_2 = NSLocalizedString("privacy-information-collected-s3-logging-para-2", tableName: nil, bundle: Bundle.main,
                                                                                value: "S3 <a href=\"https://docs.aws.amazon.com/AmazonS3/latest/dev/LogFormat.html\" target=\"_blank\">bucket access logs</a> contain IP addresses, user agents, and timestamps. These logs are stored in S3 itself, so Amazon has access to these logs. (However, Amazon already serves the files, so they can already access this information.) Psiphon developers will download the logs, aggregate and analyze the data, and then delete the logs. Raw data will be kept only long enough to aggregate it and will not be shared with third parties.",
                                                                                comment: "")
        let privacy_information_collected_vpndata_whatdoespsiphonnotdowith_para_3 = NSLocalizedString("privacy-information-collected-vpndata-whatdoespsiphonnotdowith-para-3", tableName: nil, bundle: Bundle.main,
                                                                                                      value: "We DO NOT share any sensitive or user-specific data with third parties.",
                                                                                                      comment: "Paragraph text in the 'What does Psiphon NOT do with your data?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_whatdoespsiphonnotdowith_para_2 = NSLocalizedString("privacy-information-collected-vpndata-whatdoespsiphonnotdowith-para-2", tableName: nil, bundle: Bundle.main,
                                                                                                      value: "We DO NOT modify the contents of your VPN data.",
                                                                                                      comment: "Paragraph text in the 'What does Psiphon NOT do with your data?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_psicash_para_3_item_1 = NSLocalizedString("privacy-information-collected-psicash-para-3-item-1", tableName: nil, bundle: Bundle.main,
                                                                                    value: "generated user access tokens",
                                                                                    comment: "Bullet list item in the 'data stored in web browser' list. This item refers to randomly generated values that allow a user to access and utilize the system.")
        let privacy_information_collected_mypsicash_recaptcha_para_3 = NSLocalizedString("privacy-information-collected-mypsicash-recaptcha-para-3", tableName: nil, bundle: Bundle.main,
                                                                                         value: "For more information about Google’s reCAPTCHA technology, please visit <a href=\"https://www.google.com/recaptcha/about/\" target=\"_blank\" rel=\"noopener noreferrer\">https://www.google.com/recaptcha/about/</a>.",
                                                                                         comment: "Paragraph text in the 'my.psi.cash' section of the Privacy page.")
        let privacy_information_collected_websites_head = NSLocalizedString("privacy-information-collected-websites-head", tableName: nil, bundle: Bundle.main,
                                                                            value: "Psiphon Websites",
                                                                            comment: "Sub-heading on the Privacy Policy page above the info about what data categories are collected by the Psiphon websites")
        let privacy_information_collected_psicash_para_4_item_2 = NSLocalizedString("privacy-information-collected-psicash-para-4-item-2", tableName: nil, bundle: Bundle.main,
                                                                                    value: "balance",
                                                                                    comment: "Bullet list item in the 'operation of the system' list. This item refers to the user PsiCash balance -- i.e., how much they have available to spend.")
        let privacy_information_collected_psicash_para_6 = NSLocalizedString("privacy-information-collected-psicash-para-6", tableName: nil, bundle: Bundle.main,
                                                                             value: "PsiCash server resources are stored in AWS, which means Amazon has access to the data.",
                                                                             comment: "Paragraph text in the 'PsiCash' section of the Privacy page. 'PsiCash' must not be translated or transliterated.")
        let faq_information_collected_answer_para_8_item_3 = NSLocalizedString("faq-information-collected-answer-para-8-item-3", tableName: nil, bundle: Bundle.main,
                                                                               value: "Whether your device is rooted",
                                                                               comment: "")
        let privacy_information_collected_s3_logging_head = NSLocalizedString("privacy-information-collected-s3-logging-head", tableName: nil, bundle: Bundle.main,
                                                                              value: "Storage Access Logging",
                                                                              comment: "Sub-heading for section describing use of logging access to data storage (aka S3 bucket logging). The way to read this is 'creation of logs for user accesses to data storage'. Psiphon 'stores' websites, downloads, and upgrades (the 'data') in Amazon S3 (the 'storage'). Users 'access' the data storage. And, somtimes, we 'log' those accesses. (For example, if we suspect attackers are accessing the storage, or if it seems the storage is blocked by a country.)")
        let privacy_information_collected_psicash_para_2_list_start = NSLocalizedString("privacy-information-collected-psicash-para-2-list-start", tableName: nil, bundle: Bundle.main,
                                                                                        value: "The PsiCash server stores per-user information to allow for operation of the system, including:",
                                                                                        comment: "Paragraph text in the 'PsiCash' section of the Privacy page. This is preamble to a detailed bullet list. 'PsiCash' must not be translated or transliterated.")
        let privacy_information_collected_psicash_para_1 = NSLocalizedString("privacy-information-collected-psicash-para-1", tableName: nil, bundle: Bundle.main,
                                                                             value: "The PsiCash system only collects information necessary for the functioning of the system, monitoring the health of the system, and ensuring the security of the system.",
                                                                             comment: "Paragraph text in the 'PsiCash' section of the Privacy page. 'PsiCash' must not be translated or transliterated.")
        let faq_information_collected_answer_head_4 = NSLocalizedString("faq-information-collected-answer-head-4", tableName: nil, bundle: Bundle.main,
                                                                        value: "App Stores",
                                                                        comment: "this is referring to the general idea of app stores, like the Google Play Store, Amazon AppStore, Apple App Store")
        let privacy_information_collected_websites_google_analytics_para_3 = NSLocalizedString("privacy-information-collected-websites-google-analytics-para-3", tableName: nil, bundle: Bundle.main,
                                                                                               value: "Google’s ability to use and share information collected by Google Analytics about your visits to this site is restricted by the <a href=\"http://www.google.ca/analytics/terms/us.html\" target=\"_blank\">Google Analytics Terms of Use</a> and the <a href=\"http://www.google.com/policies/privacy/\" target=\"_blank\">Google Privacy Policy</a>. You may choose to opt out by turning off cookies in the preferences settings in your web browser.",
                                                                                               comment: "")
        let privacy_information_collected_s3_logging_para_1 = NSLocalizedString("privacy-information-collected-s3-logging-para-1", tableName: nil, bundle: Bundle.main,
                                                                                value: "We use Amazon S3 to store assets such as website files and Psiphon server discovery lists. We sometimes enable logging of downloads of these files. Analyzing these logs helps us to answer questions like \"how many users are starting but not completing the download of the server discovery list?\", \"how is the downloaded data split between website assets and server discovery?\", and \"is an attacker making a denial-of-service attempt against our websites?\"",
                                                                                comment: "")
        let privacy_information_collected_vpndata_aggdata_para_3 = NSLocalizedString("privacy-information-collected-vpndata-aggdata-para-3", tableName: nil, bundle: Bundle.main,
                                                                                     value: "Aggregated data is much less sensitive than activity data, but we still treat it as potentially sensitive and do not share it in this form.",
                                                                                     comment: "Paragraph text in the 'Aggregated Data' definition subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_psicash_para_2_item_5 = NSLocalizedString("privacy-information-collected-psicash-para-2-item-5", tableName: nil, bundle: Bundle.main,
                                                                                    value: "PsiCash spending history, including what purchases were made",
                                                                                    comment: "Bullet list item in the 'operation of the system' list. This item refers to transaction history of the user spending PsiCash, such as by buying Speed Boost. 'PsiCash' must not be translated or transliterated.")
        let faq_information_collected_answer_para_7_list_start = NSLocalizedString("faq-information-collected-answer-para-7-list-start", tableName: nil, bundle: Bundle.main,
                                                                                   value: "Windows:",
                                                                                   comment: "")
        let privacy_information_collected_vpndata_kindsofdata_para_1 = NSLocalizedString("privacy-information-collected-vpndata-kindsofdata-para-1", tableName: nil, bundle: Bundle.main,
                                                                                         value: "We will define some categories of data to help us talk about them in the context of Psiphon.",
                                                                                         comment: "Paragraph text in the 'What kinds of user data does Psiphon collect?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_psicash_para_4_item_4 = NSLocalizedString("privacy-information-collected-psicash-para-4-item-4", tableName: nil, bundle: Bundle.main,
                                                                                    value: "client version",
                                                                                    comment: "Bullet list item in the 'operation of the system' list. This item refers to the version of the Psiphon app.")
        let privacy_information_collected_mypsicash_cookies_para_1 = NSLocalizedString("privacy-information-collected-mypsicash-cookies-para-1", tableName: nil, bundle: Bundle.main,
                                                                                       value: "my.psi.cash only uses cookies and similar tracking technologies to carry out activities that are essential for the operation of the website. Essential cookies are necessary to ensure basic functions of the website. Cookies are small text files that are stored on your computer and saved by your browser, and do not represent any risk to your device. You can configure your browser settings to personalize how you would like your browser to handle cookies. Disabling essential cookies will degrade the functionality of this website.",
                                                                                       comment: "Paragraph text in the 'my.psi.cash' section of the Privacy page. 'my.psi.cash' is the domain name of the website and must not be translated or transliterated.")
        let faq_information_collected_answer_para_13_item_3 = NSLocalizedString("faq-information-collected-answer-para-13-item-3", tableName: nil, bundle: Bundle.main,
                                                                                value: "The size of the email.",
                                                                                comment: "")
        let privacy_information_collected_psicash_para_4_item_5 = NSLocalizedString("privacy-information-collected-psicash-para-4-item-5", tableName: nil, bundle: Bundle.main,
                                                                                    value: "PsiCash earning and spending details",
                                                                                    comment: "Bullet list item in the 'operation of the system' list. This item refers to transaction history of the user earning and spending PsiCash. 'PsiCash' must not be translated or transliterated.")
        let privacy_information_collected_vpndata_whydoespsiphonneed_para_1_item_4 = NSLocalizedString("privacy-information-collected-vpndata-whydoespsiphonneed-para-1-item-4", tableName: nil, bundle: Bundle.main,
                                                                                                       value: "Understand who we need to help: Some sites and services will never get blocked anywhere, some will always be blocked in certain countries, and some will occasionally be blocked in some countries. To make sure that our users are able to communicate and learn freely, we need to understand these patterns, see who is affected, and work with partners to make sure their services work best with Psiphon.",
                                                                                                       comment: "Bullet list text under 'What does Psiphon do with User Activity and Aggregated Data?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_whatdoespsiphonnotdowith_para_1 = NSLocalizedString("privacy-information-collected-vpndata-whatdoespsiphonnotdowith-para-1", tableName: nil, bundle: Bundle.main,
                                                                                                      value: "We DO NOT collect or store any VPN data that is not mentioned here.",
                                                                                                      comment: "Paragraph text in the 'What does Psiphon NOT do with your data?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_whatdoespsiphondowith_para_2_item_3 = NSLocalizedString("privacy-information-collected-vpndata-whatdoespsiphondowith-para-2-item-3", tableName: nil, bundle: Bundle.main,
                                                                                                          value: "Ensure users stay connected while foiling censors: We try to detect that a user is behaving like a real person and then reveal new Psiphon servers to them. (This is our obfuscated server list technology.)",
                                                                                                          comment: "Bullet list text under 'What does Psiphon do with User Activity and Aggregated Data?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let faq_information_collected_answer_para_11 = NSLocalizedString("faq-information-collected-answer-para-11", tableName: nil, bundle: Bundle.main,
                                                                         value: "When you send an email request to our email auto-responder server, we are able to see your email address. While your email is being processed it is saved to the email server's disk, and it is deleted as soon as it is processed (usually in a few seconds). Your email address may be written to the server system logs. These logs are deleted after one week.",
                                                                         comment: "")
        let privacy_information_collected_client_ads_head = NSLocalizedString("privacy-information-collected-client-ads-head", tableName: nil, bundle: Bundle.main,
                                                                              value: "Psiphon Client Advertising Networks",
                                                                              comment: "Sub-heading on the Privacy Policy page above the info about what data categories are collected by the ads shown in the Psiphon client software")
        let privacy_information_collected_client_advertising_networks_para_2 = NSLocalizedString("privacy-information-collected-client-advertising-networks-para-2", tableName: nil, bundle: Bundle.main,
                                                                                                 value: "You can opt out of the use of cookies for interest-based advertising by visiting:",
                                                                                                 comment: "")
        let privacy_information_collected_vpndata_shareable_para_3 = NSLocalizedString("privacy-information-collected-vpndata-shareable-para-3", tableName: nil, bundle: Bundle.main,
                                                                                       value: "An example of shareable aggregated data might be: On a particular day, 500 people connected from New York City and transferred 800GB in total.",
                                                                                       comment: "Paragraph text in the 'Shareable Aggregated Data' definition subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_mypsicash_cookies_head = NSLocalizedString("privacy-information-collected-mypsicash-cookies-head", tableName: nil, bundle: Bundle.main,
                                                                                     value: "Cookies",
                                                                                     comment: "Header text in the 'my.psi.cash' section of the Privacy page. Refers to the cookies stored by web browsers.")
        let privacy_information_collected_vpndata_shareable_subhead = NSLocalizedString("privacy-information-collected-vpndata-shareable-subhead", tableName: nil, bundle: Bundle.main,
                                                                                        value: "Shareable Aggregated Data",
                                                                                        comment: "Sub-heading for the definition of 'Shareable Aggregated Data' under the 'User Activity and VPN Data' section of the Privacy Policy page.")
        let privacy_information_collected_psicash_para_5 = NSLocalizedString("privacy-information-collected-psicash-para-5", tableName: nil, bundle: Bundle.main,
                                                                             value: "Individual user data is never shared with third parties. Coarse aggregate statistics may be shared, but never in a form that can possibly identify users.",
                                                                             comment: "Paragraph text in the 'PsiCash' section of the Privacy page. 'PsiCash' must not be translated or transliterated.")
        let faq_information_collected_answer_para_13_item_2 = NSLocalizedString("faq-information-collected-answer-para-13-item-2", tableName: nil, bundle: Bundle.main,
                                                                                value: "The date and time the email request was replied to.",
                                                                                comment: "")
        let privacy_canadian_privacy_commission_link_text = NSLocalizedString("privacy-canadian-privacy-commission-link-text", tableName: nil, bundle: Bundle.main,
                                                                              value: "Office of the Privacy Commissioner of Canada",
                                                                              comment: "")
        let privacy_information_collected_vpndata_head_v2 = NSLocalizedString("privacy-information-collected-vpndata-head-v2", tableName: nil, bundle: Bundle.main,
                                                                              value: "User Activity and VPN Data",
                                                                              comment: "Sub-heading on the Privacy Policy page for the section describing handling of user traffic data and activity statistics through the Psiphon VPN")
        let privacy_information_collected_vpndata_whatdoespsiphonnotdowith_subhead = NSLocalizedString("privacy-information-collected-vpndata-whatdoespsiphonnotdowith-subhead", tableName: nil, bundle: Bundle.main,
                                                                                                       value: "What does Psiphon <strong>NOT</strong> do with your data?",
                                                                                                       comment: "Sub-heading in the 'User Activity and VPN Data' section of the Privacy Policy page. The section describes what undesirable things Psiphon DOES NOT do with user data. '<strong>' is an HTML tag that makes text bold, which can be used if it makes sense in your language.")
        let privacy_information_collected_vpndata_whatdoespsiphondowith_subhead_v2 = NSLocalizedString("privacy-information-collected-vpndata-whatdoespsiphondowith-subhead-v2", tableName: nil, bundle: Bundle.main,
                                                                                                       value: "What does Psiphon do with User Activity and Aggregated Data?",
                                                                                                       comment: "Sub-heading in the 'User Activity and VPN Data' section of the Privacy Policy page. The section describes what Psiphon does with the little bit of VPN data that it collects stats from.")
        let privacy_information_collected_mypsicash_recaptcha_para_1 = NSLocalizedString("privacy-information-collected-mypsicash-recaptcha-para-1", tableName: nil, bundle: Bundle.main,
                                                                                         value: "my.psi.cash uses Google’s reCAPTCHA v3 (hereinafter “reCAPTCHA”), which protects websites from spam and abuse by non-human users (i.e., bots). reCAPTCHA collects personal information that is required for the functioning of the technology and is subject to its own privacy policy. Use of my.psi.cash indicates acceptance of Google’s <a href=\"https://policies.google.com/privacy\" target=\"_blank\" rel=\"noopener noreferrer\">Privacy Policy</a> and <a href=\"https://policies.google.com/terms\" target=\"_blank\" rel=\"noopener noreferrer\">Terms</a>.",
                                                                                         comment: "Paragraph text in the 'my.psi.cash' section of the Privacy page. 'my.psi.cash' is the domain name of the website and must not be translated or transliterated.")
        let privacy_information_collected_vpndata_whydoespsiphonneed_para_1_item_3 = NSLocalizedString("privacy-information-collected-vpndata-whydoespsiphonneed-para-1-item-3", tableName: nil, bundle: Bundle.main,
                                                                                                       value: "Determine the nature of major censorship events: Sites and services often get blocked suddenly and without warning, which can lead to huge variations in regional usage of Psiphon. For example, we had up to 20x surges in usage within a day when <a href=\"https://blog-en.psiphon.ca/2016/07/psiphon-usage-surges-as-brazil-blocks.html\" target=\"_blank\">Brazil blocked WhatsApp</a> or <a href=\"https://blog-en.psiphon.ca/2016/11/social-media-and-internet-ban-in-turkey.html\" target=\"_blank\">Turkey blocked social media</a>.",
                                                                                                       comment: "Bullet list text under 'What does Psiphon do with User Activity and Aggregated Data?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_aggdata_para_1 = NSLocalizedString("privacy-information-collected-vpndata-aggdata-para-1", tableName: nil, bundle: Bundle.main,
                                                                                     value: "Data is “aggregated” by taking a lot of sensitive user activity data and combining it together to form coarse statistical data that is no longer specific to a user. After aggregation, the user activity data is deleted.",
                                                                                     comment: "Paragraph text in the 'Aggregated Data' definition subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let faq_information_collected_answer_para_13_item_1 = NSLocalizedString("faq-information-collected-answer-para-13-item-1", tableName: nil, bundle: Bundle.main,
                                                                                value: "The date and time the email request was received.",
                                                                                comment: "")
        let faq_information_collected_answer_para_13_item_4 = NSLocalizedString("faq-information-collected-answer-para-13-item-4", tableName: nil, bundle: Bundle.main,
                                                                                value: "The mail server the email request came from. (The three least specific parts of the domain name. For example, <code>ne1.example.com</code>, but not <code>web120113.mail.ne1.example.com</code>.)",
                                                                                comment: "")
        let privacy_information_collected_vpndata_useractivity_para_1 = NSLocalizedString("privacy-information-collected-vpndata-useractivity-para-1", tableName: nil, bundle: Bundle.main,
                                                                                          value: "While a user's device is tunneled through Psiphon, we collect some information about how they're using it. We record what protocol Psiphon used to connect, how long the device was connected, how many bytes were transferred during the session, and what city, country, and ISP the connection came from. For some domains (but very few, and only popular ones) or server IP addresses (e.g., known malware servers) that are visited, we also record how many bytes were transferred to it. (But never full URLs or anything more sensitive. And only domains of general interest, not all domains.)",
                                                                                          comment: "Paragraph text in the 'User Activity Data' definition subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_whopsiphonshareswith_para_3_v2 = NSLocalizedString("privacy-information-collected-vpndata-whopsiphonshareswith-para-3-v2", tableName: nil, bundle: Bundle.main,
                                                                                                     value: "Again, only anonymized shareable aggregated data is ever shared with third parties.",
                                                                                                     comment: "Paragraph text in the 'Who does Psiphon share these statistics with?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_websites_google_analytics_para_2 = NSLocalizedString("privacy-information-collected-websites-google-analytics-para-2", tableName: nil, bundle: Bundle.main,
                                                                                               value: "Google Analytics sets a permanent cookie in your web browser to identify you as a unique user the next time you visit the site, but this cookie cannot be used by anyone except Google, and the data collected cannot be altered or retrieved by services from other domains.",
                                                                                               comment: "")
        let privacy_information_collected_psicash_para_2_item_3 = NSLocalizedString("privacy-information-collected-psicash-para-2-item-3", tableName: nil, bundle: Bundle.main,
                                                                                    value: "last activity timestamp",
                                                                                    comment: "Bullet list item in the 'operation of the system' list. This item refers to the date and time that the user last earned or spent PsiCash.")
        let privacy_information_collected_vpndata_whycare_para_1 = NSLocalizedString("privacy-information-collected-vpndata-whycare-para-1", tableName: nil, bundle: Bundle.main,
                                                                                     value: "When using a VPN or proxy you should be concerned about what the VPN provider can see in your data, collect from it, and do to it.",
                                                                                     comment: "Paragraph text in the 'Why should you care?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let faq_information_collected_answer_para_8_item_1 = NSLocalizedString("faq-information-collected-answer-para-8-item-1", tableName: nil, bundle: Bundle.main,
                                                                               value: "Android version",
                                                                               comment: "")
        let privacy_information_collected_psicash_para_4_item_1 = NSLocalizedString("privacy-information-collected-psicash-para-4-item-1", tableName: nil, bundle: Bundle.main,
                                                                                    value: "user country",
                                                                                    comment: "Bullet list item in the 'system health and security' list. This item refers to the country from which a user was connecting when he/she performed an action.")
        let privacy_information_collected_vpndata_whycare_para_3 = NSLocalizedString("privacy-information-collected-vpndata-whycare-para-3", tableName: nil, bundle: Bundle.main,
                                                                                     value: "For unencrypted services, it is possible for a VPN provider to see, collect, and modify (e.g., injecting ads into) the contents of your data. For encrypted data, it is still possible for a VPN to collect metadata about sites visited or actions taken. You should also be concerned with your VPN provider sharing your data with third parties.",
                                                                                     comment: "Paragraph text in the 'Why should you care?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_psicash_para_4_list_start = NSLocalizedString("privacy-information-collected-psicash-para-4-list-start", tableName: nil, bundle: Bundle.main,
                                                                                        value: "For monitoring system health and security, system activity data is collected and aggregated. This data includes:",
                                                                                        comment: "Paragraph text in the 'PsiCash' section of the Privacy page. This is preamble to a detailed bullet list. 'PsiCash' must not be translated or transliterated.")
        let privacy_information_collected_vpndata_whydoespsiphonneed_para_1_item_1 = NSLocalizedString("privacy-information-collected-vpndata-whydoespsiphonneed-para-1-item-1", tableName: nil, bundle: Bundle.main,
                                                                                                       value: "Estimate future costs: The huge amount of user data we transfer each month is a major factor in our costs. It is vital for us to see and understand usage fluctuations.",
                                                                                                       comment: "Bullet list text under 'What does Psiphon do with User Activity and Aggregated Data?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_whopsiphonshareswith_para_2_item_1 = NSLocalizedString("privacy-information-collected-vpndata-whopsiphonshareswith-para-2-item-1", tableName: nil, bundle: Bundle.main,
                                                                                                         value: "How well Psiphon is working in a particular region.",
                                                                                                         comment: "Bullet list text under 'Who does Psiphon share Aggregated Data with?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let faq_information_collected_answer_head_3 = NSLocalizedString("faq-information-collected-answer-head-3", tableName: nil, bundle: Bundle.main,
                                                                        value: "Email Responder",
                                                                        comment: "")
        let faq_information_collected_answer_para_7_item_1 = NSLocalizedString("faq-information-collected-answer-para-7-item-1", tableName: nil, bundle: Bundle.main,
                                                                               value: "Operating system version",
                                                                               comment: "")
        let privacy_information_collected_psicash_para_2_item_4 = NSLocalizedString("privacy-information-collected-psicash-para-2-item-4", tableName: nil, bundle: Bundle.main,
                                                                                    value: "PsiCash earning history, including what actions the rewards were granted for",
                                                                                    comment: "Bullet list item in the 'operation of the system' list. This item refers to transaction history of the user earning PsiCash. 'PsiCash' must not be translated or transliterated.")
        let privacy_information_collected_websites_google_analytics_head = NSLocalizedString("privacy-information-collected-websites-google-analytics-head", tableName: nil, bundle: Bundle.main,
                                                                                             value: "Google Analytics",
                                                                                             comment: "Sub-heading for section describing use of Google Analytics and what info they collect")
        let faq_information_collected_answer_head_2 = NSLocalizedString("faq-information-collected-answer-head-2", tableName: nil, bundle: Bundle.main,
                                                                        value: "Feedback",
                                                                        comment: "")
        let privacy_information_collected_vpndata_whopsiphonshareswith_subhead_v2 = NSLocalizedString("privacy-information-collected-vpndata-whopsiphonshareswith-subhead-v2", tableName: nil, bundle: Bundle.main,
                                                                                                      value: "Who does Psiphon share Aggregated Data with?",
                                                                                                      comment: "Sub-heading in the 'User Activity and VPN Data' section of the Privacy Policy page. The section describes who Psiphon shares VPN data stats. The answer will be organizations and not specific people, in case that makes a difference in your language.")
        let privacy_information_collected_psicash_para_3_item_2 = NSLocalizedString("privacy-information-collected-psicash-para-3-item-2", tableName: nil, bundle: Bundle.main,
                                                                                    value: "when a PsiCash reward is allowed to be claimed again",
                                                                                    comment: "Bullet list item in the 'data stored in web browser' list. PsiCash earning rewards can only be claimed every so often in the web browser, so this refers to the date-time when the user is next allowed to claim a reward. 'PsiCash' must not be translated or transliterated.")
        let faq_information_collected_answer_para_7_item_2 = NSLocalizedString("faq-information-collected-answer-para-7-item-2", tableName: nil, bundle: Bundle.main,
                                                                               value: "Anti-virus version",
                                                                               comment: "")
        let privacy_information_collected_vpndata_shareable_para_4 = NSLocalizedString("privacy-information-collected-vpndata-shareable-para-4", tableName: nil, bundle: Bundle.main,
                                                                                       value: "An example of data that is <em>not shareable</em>: On a particular day, 2 people connected from Los Angeles. Those people will be included in the stats for the entire US, but that is too few people to anonymously share city data for.",
                                                                                       comment: "Paragraph text in the 'Shareable Aggregated Data' definition subsection of the 'User Activity and VPN Data' section of the Privacy page. '<em>' is an HTML tag that adds emphasis (like italics), which can be used if it makes sense in your language.")
        let privacy_information_collected_vpndata_useractivity_para_4_1 = NSLocalizedString("privacy-information-collected-vpndata-useractivity-para-4.1", tableName: nil, bundle: Bundle.main,
                                                                                            value: "We consider user activity data the most sensitive category of data. We never, ever share this data with third parties. We keep user activity data for at most 90 days, and then we aggregate it and delete it. Backups of that data are kept for a reasonable amount of time.",
                                                                                            comment: "Paragraph text in the 'User Activity Data' definition subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_psicash_para_2_item_2 = NSLocalizedString("privacy-information-collected-psicash-para-2-item-2", tableName: nil, bundle: Bundle.main,
                                                                                    value: "balance",
                                                                                    comment: "Bullet list item in the 'operation of the system' list. This item refers to the user PsiCash balance -- i.e., how much they have available to spend.")
        let faq_information_collected_answer_para_13 = NSLocalizedString("faq-information-collected-answer-para-13", tableName: nil, bundle: Bundle.main,
                                                                         value: "For each email we receive, we store the following information:",
                                                                         comment: "")
        let privacy_information_collected_vpndata_shareable_para_2 = NSLocalizedString("privacy-information-collected-vpndata-shareable-para-2", tableName: nil, bundle: Bundle.main,
                                                                                       value: "We also never share domain-related information with third parties.",
                                                                                       comment: "Paragraph text in the 'Shareable Aggregated Data' definition subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_whatdoespsiphondowith_para_1_v2 = NSLocalizedString("privacy-information-collected-vpndata-whatdoespsiphondowith-para-1-v2", tableName: nil, bundle: Bundle.main,
                                                                                                      value: "Activity and aggregated statistical data are vital for us to make Psiphon work best. It allows us to do things like:",
                                                                                                      comment: "Paragraph text in the 'What does Psiphon do with User Activity and Aggregated Data?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let privacy_information_collected_vpndata_whatdoespsiphondowith_para_2_item_1 = NSLocalizedString("privacy-information-collected-vpndata-whatdoespsiphondowith-para-2-item-1", tableName: nil, bundle: Bundle.main,
                                                                                                          value: "Monitor the health and success of the Psiphon network: We need to know how many people are connecting, from where, how much data they're transferring, and if they're having any problems.",
                                                                                                          comment: "Bullet list text under 'What does Psiphon do with User Activity and Aggregated Data?' subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        let faq_information_collected_answer_para_10 = NSLocalizedString("faq-information-collected-answer-para-10", tableName: nil, bundle: Bundle.main,
                                                                         value: "Note that if you get Psiphon from an \"app store\", such as the Google Play Store or Amazon AppStore, additional statistics may be collected by that store. For example, here is a description of what the Google Play Store collects:",
                                                                         comment: "")
        let faq_information_collected_answer_para_7_item_4 = NSLocalizedString("faq-information-collected-answer-para-7-item-4", tableName: nil, bundle: Bundle.main,
                                                                               value: "How much free memory your computer has",
                                                                               comment: "")
        let privacy_information_collected_mypsicash_recaptcha_para_2 = NSLocalizedString("privacy-information-collected-mypsicash-recaptcha-para-2", tableName: nil, bundle: Bundle.main,
                                                                                         value: "Our use of reCAPTCHA is strictly limited to ensuring the continued functioning of my.psi.cash. reCAPTCHA technology performs an automatic analysis for each site request without requiring the user to take any additional actions. This analysis is based on interactions made by the user, and is used to mitigate bot and other malicious behaviour on our website. The data collected during analysis is forwarded to Google, where Google will use this data to determine if you are a human user. This analysis takes place in the background, and users are not advised it is taking place.",
                                                                                         comment: "Paragraph text in the 'my.psi.cash' section of the Privacy page. 'my.psi.cash' is the domain name of the website and must not be translated or transliterated.")
        let faq_information_collected_answer_para_6 = NSLocalizedString("faq-information-collected-answer-para-6", tableName: nil, bundle: Bundle.main,
                                                                        value: "When you choose to submit feedback through Psiphon you will have the option of including diagnostic data. We use this data to help us troubleshoot any problems you might be having and to help us keep Psiphon running smoothly. Sending this data is entirely optional. The data is encrypted before you send it, and can only be decrypted by us. The information in the data varies by platform, but it may include:",
                                                                        comment: "")
        let faq_information_collected_answer_para_12 = NSLocalizedString("faq-information-collected-answer-para-12", tableName: nil, bundle: Bundle.main,
                                                                         value: "Our email auto-responder server is hosted in the Amazon EC2 cloud. This means that Amazon is able to see the email you send and our response to you.",
                                                                         comment: "")
        let faq_information_collected_answer_para_7_item_3 = NSLocalizedString("faq-information-collected-answer-para-7-item-3", tableName: nil, bundle: Bundle.main,
                                                                               value: "How you're connected to the internet (for example, if you're using dial-up or connected via a proxy)",
                                                                               comment: "")
        let privacy_information_collected_vpndata_useractivity_para_2 = NSLocalizedString("privacy-information-collected-vpndata-useractivity-para-2", tableName: nil, bundle: Bundle.main,
                                                                                          value: "Geographical location and ISP info are derived from user IP addresses, which are then immediately discarded.",
                                                                                          comment: "Paragraph text in the 'User Activity Data' definition subsection of the 'User Activity and VPN Data' section of the Privacy page.")
        
        return """
            <h2>\(privacy_information_collected_data_categories_header)</h2>
        <!-- User VPN Data -->
        <h3>\(privacy_information_collected_vpndata_head_v2)</h3>
        <h4>\(privacy_information_collected_vpndata_whycare_subhead)</h4>
        <p> \(privacy_information_collected_vpndata_whycare_para_1) </p>
        <p> \(privacy_information_collected_vpndata_whycare_para_2) </p>
        <p> \(privacy_information_collected_vpndata_whycare_para_3) </p>
        <h4>\(privacy_information_collected_vpndata_whatdoespsiphonnotdowith_subhead)</h4>
        <p> \(privacy_information_collected_vpndata_whatdoespsiphonnotdowith_para_1) </p>
        <p> \(privacy_information_collected_vpndata_whatdoespsiphonnotdowith_para_2) </p>
        <p> \(privacy_information_collected_vpndata_whatdoespsiphonnotdowith_para_3) </p>
        <h4>\(privacy_information_collected_vpndata_kindsofdata_subhead)</h4>
        <p> \(privacy_information_collected_vpndata_kindsofdata_para_1) </p>
        <h5><em>\(privacy_information_collected_vpndata_useractivity_subhead)</em></h5>
        <p> \(privacy_information_collected_vpndata_useractivity_para_1) </p>
        <p> \(privacy_information_collected_vpndata_useractivity_para_2) </p>
        <p> \(privacy_information_collected_vpndata_useractivity_para_3) </p>
        <p> \(privacy_information_collected_vpndata_useractivity_para_4_1) </p>
        <h5><em>\(privacy_information_collected_vpndata_aggdata_subhead)</em></h5>
        <p> \(privacy_information_collected_vpndata_aggdata_para_1) </p>
        <p> \(privacy_information_collected_vpndata_aggdata_para_2) </p>
        <p> \(privacy_information_collected_vpndata_aggdata_para_3) </p>
        <h5><em>\(privacy_information_collected_vpndata_shareable_subhead)</em></h5>
        <p> \(privacy_information_collected_vpndata_shareable_para_1) </p>
        <p> \(privacy_information_collected_vpndata_shareable_para_2) </p>
        <p> \(privacy_information_collected_vpndata_shareable_para_3) </p>
        <p> \(privacy_information_collected_vpndata_shareable_para_4) </p>
        <h4>\(privacy_information_collected_vpndata_whatdoespsiphondowith_subhead_v2)</h4>
        <p> \(privacy_information_collected_vpndata_whatdoespsiphondowith_para_1_v2) </p>
        <ul>
        <li>\(privacy_information_collected_vpndata_whatdoespsiphondowith_para_2_item_1)</li>
        <li>\(privacy_information_collected_vpndata_whatdoespsiphondowith_para_2_item_2)</li>
        <li>\(privacy_information_collected_vpndata_whatdoespsiphondowith_para_2_item_3)</li>
        <li>\(privacy_information_collected_vpndata_whydoespsiphonneed_para_1_item_1)</li>
        <li>\(privacy_information_collected_vpndata_whydoespsiphonneed_para_1_item_3)</li>
        <li>\(privacy_information_collected_vpndata_whydoespsiphonneed_para_1_item_4)</li>
        </ul>
        <h4>\(privacy_information_collected_vpndata_whopsiphonshareswith_subhead_v2)</h4>
        <p> \(privacy_information_collected_vpndata_whopsiphonshareswith_para_1_v2) </p>
        <ul>
        <li>\(privacy_information_collected_vpndata_whopsiphonshareswith_para_2_item_1)</li>
        <li>\(privacy_information_collected_vpndata_whopsiphonshareswith_para_2_item_2)</li>
        <li>\(privacy_information_collected_vpndata_whopsiphonshareswith_para_2_item_3)</li>
        </ul>
        <p> \(privacy_information_collected_vpndata_whopsiphonshareswith_para_3_v2) </p>
        <!-- Psiphon Client Advertising Networks -->
        <h3>\(privacy_information_collected_client_ads_head)</h3>
        <p> \(privacy_information_collected_client_advertising_networks_para_1) </p>
        <ul>
        <li> <a href="https://freestar.com/data-policy/">https://freestar.com/data-policy/</a> </li>
        <li> <a href="https://ogury.com/privacy-policy/">https://ogury.com/privacy-policy/</a> </li>
        <li> <a href="https://policies.google.com/privacy">https://policies.google.com/privacy</a> </li>
        <li> <a href="https://policies.google.com/technologies/partner-sites">https://policies.google.com/technologies/partner-sites</a> </li>
        <li> <a href="https://unity3d.com/legal/privacy-policy">https://unity3d.com/legal/privacy-policy</a> </li>
        <li> <a href="https://vungle.com/privacy/">https://vungle.com/privacy/</a> </li>
        <li> <a href="https://www.amazon.com/gp/help/customer/display.html?nodeId=468496">https://www.amazon.com/gp/help/customer/display.html?nodeId=468496</a> </li>
        <li> <a href="https://www.applovin.com/privacy/">https://www.applovin.com/privacy/</a> </li>
        <li> <a href="https://www.facebook.com/policy.php">https://www.facebook.com/policy.php</a> </li>
        <li> <a href="https://www.mopub.com/legal/privacy/">https://www.mopub.com/legal/privacy/</a> </li>
        <li> <a href="https://www.mopub.com/legal/partners/">https://www.mopub.com/legal/partners/</a> </li>
        <li> <a href="https://www.verizonmedia.com/policies/us/en/verizonmedia/privacy/index.html">https://www.verizonmedia.com/policies/us/en/verizonmedia/privacy/index.html</a> </li>
        </ul>
        <p> \(privacy_information_collected_client_advertising_networks_para_2) </p>
        <ul>
        <li> <a href="https://www.mopub.com/optout/">https://www.mopub.com/optout/</a> </li>
        </ul>
        <!-- Websites -->
        <h3>\(privacy_information_collected_websites_head)</h3>
        <h4>\(privacy_information_collected_websites_google_analytics_head)</h4>
        <p> \(privacy_information_collected_websites_google_analytics_para_1) </p>
        <p> \(privacy_information_collected_websites_google_analytics_para_2) </p>
        <p> \(privacy_information_collected_websites_google_analytics_para_3) </p>
        <h4>\(privacy_information_collected_s3_logging_head)</h4>
        <p> \(privacy_information_collected_s3_logging_para_1) </p>
        <p> \(privacy_information_collected_s3_logging_para_2) </p>
        <!-- PsiCash -->
        <h3>PsiCash</h3>
        <p> \(privacy_information_collected_psicash_para_1) </p>
        <p> \(privacy_information_collected_psicash_para_2_list_start) </p>
        <ul>
        <li>\(privacy_information_collected_psicash_para_2_item_1)</li>
        <li>\(privacy_information_collected_psicash_para_2_item_2)</li>
        <li>\(privacy_information_collected_psicash_para_2_item_3)</li>
        <li>\(privacy_information_collected_psicash_para_2_item_4)</li>
        <li>\(privacy_information_collected_psicash_para_2_item_5)</li>
        </ul>
        <p> \(privacy_information_collected_psicash_para_2b) </p>
        <p> \(privacy_information_collected_psicash_para_3_list_start) </p>
        <ul>
        <li>\(privacy_information_collected_psicash_para_3_item_1)</li>
        <li>\(privacy_information_collected_psicash_para_3_item_2)</li>
        </ul>
        <p> \(privacy_information_collected_psicash_para_4_list_start) </p>
        <ul>
        <li>\(privacy_information_collected_psicash_para_4_item_1)</li>
        <li>\(privacy_information_collected_psicash_para_4_item_2)</li>
        <li>\(privacy_information_collected_psicash_para_4_item_3)</li>
        <li>\(privacy_information_collected_psicash_para_4_item_4)</li>
        <li>\(privacy_information_collected_psicash_para_4_item_5)</li>
        </ul>
        <p> \(privacy_information_collected_psicash_para_5) </p>
        <p> \(privacy_information_collected_psicash_para_6) </p>
        <!-- my.psi.cash -->
        <h4>my.psi.cash</h4>
        <p> \(privacy_information_collected_mypsicash_para_1) </p>
        <h5>reCAPTCHA</h5>
        <p> \(privacy_information_collected_mypsicash_recaptcha_para_1) </p>
        <p> \(privacy_information_collected_mypsicash_recaptcha_para_2) </p>
        <p> \(privacy_information_collected_mypsicash_recaptcha_para_3) </p>
        <h5>\(privacy_information_collected_mypsicash_cookies_head)</h5>
        <p> \(privacy_information_collected_mypsicash_cookies_para_1) </p>
        <!-- Feedback -->
        <h3>\(faq_information_collected_answer_head_2)</h3>
        <p> \(faq_information_collected_answer_para_6) </p>
        <p> \(faq_information_collected_answer_para_7_list_start) </p>
        <ul>
        <li>\(faq_information_collected_answer_para_7_item_1)</li>
        <li>\(faq_information_collected_answer_para_7_item_2)</li>
        <li>\(faq_information_collected_answer_para_7_item_3)</li>
        <li>\(faq_information_collected_answer_para_7_item_4)</li>
        </ul>
        <p> \(faq_information_collected_answer_para_8_list_start) </p>
        <ul>
        <li>\(faq_information_collected_answer_para_8_item_1)</li>
        <li>\(faq_information_collected_answer_para_8_item_2)</li>
        <li>\(faq_information_collected_answer_para_8_item_3)</li>
        </ul>
        <!-- Email Responder -->
        <h3>\(faq_information_collected_answer_head_3)</h3>
        <p> \(faq_information_collected_answer_para_11) </p>
        <p> \(faq_information_collected_answer_para_12) </p>
        <p> \(faq_information_collected_answer_para_13) </p>
        <ul>
        <li>\(faq_information_collected_answer_para_13_item_1)</li>
        <li>\(faq_information_collected_answer_para_13_item_2)</li>
        <li>\(faq_information_collected_answer_para_13_item_3)</li>
        <li>\(faq_information_collected_answer_para_13_item_4)</li>
        </ul>
        <!-- App Stores -->
        <h3>\(faq_information_collected_answer_head_4)</h3>
        <p> \(faq_information_collected_answer_para_10) <a href="https://support.google.com/googleplay/android-developer/answer/139628?hl=\(languageCode)" target="_blank">https://support.google.com/googleplay/android-developer/answer/139628?hl=\(languageCode)</a> </p>
        """
    }
    
}
