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
                                 comment: "Alert message informing user that a Psip")
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
    
    static func Purchase_not_recorded_by_AppStore() -> String {
        return NSLocalizedString("PURCHASE_NOT_RECORDED_BY_APPSTORE", tableName: nil, bundle: Bundle.main,
                                 value: "Purchase not recorded by App Store.",
                                 comment: "'App Store' refers to Apple's App Store, do not translate or transliterate 'App Store'. This alert message informs the user that the purchase they made has not been recorded by App Store.")
    }
    
    static func Refresh_app_receipt_to_try_again() -> String {
        return NSLocalizedString("REFRESH_APP_RECEIPT_TO_TRY_AGAIN", tableName: nil, bundle: Bundle.main,
                                 value: "Refresh the app receipt to try again.",
                                 comment: "This alert message informs the user that the purchase they made has not been recorded and that they can tap the button 'Refresh Receipt' to try again.")
    }
    
    static func Refresh_receipt_button_title() -> String {
        return NSLocalizedString("RECEIPT_REFRESH_BUTTON", tableName: nil, bundle: Bundle.main,
                                 value: "Refresh Receipt",
                                 comment: "Button title on an error alert that indicates it refreshes the user's purchase receipt on device.")
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

    @objc static func Reset_admob_consent() -> String {
        return NSLocalizedString("SETTINGS_RESET_ADMOB_CONSENT", tableName: nil, bundle: Bundle.main,
                                 value: "Reset AdMob Consent",
                                 comment: "(Do not translate 'AdMob') Title of cell in settings menu which indicates the user can change or revoke the consent they've given to admob")
    }
    
    @objc static func Logout_of_psicash_account() -> String {
        return NSLocalizedString("LOG_OUT_PSICASH_ACCOUNT", tableName: nil, bundle: Bundle.main,
                                 value: "Log out of PsiCash account",
                                 comment: "Do not translate or transliterate 'PsiCash'. Settings menu logout button that lets users log out of their PsiCash account.")
    }
    
    @objc static func Are_you_sure_psicash_account_logout() -> String {
        return NSLocalizedString("PSICASH_ACCOUNT_LOGOUT_CHECK_PROMPT", tableName: nil, bundle: Bundle.main,
                                 value: "Are you sure you want to log out of your PsiCash account?",
                                 comment: "Do not translate or transliterate 'PsiCash'. Alert message asking user if they are sure they would like to logout of their PsiCash account")
    }
    
    @objc static func Log_out() -> String {
        return NSLocalizedString("LOG_OUT_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Log Out",
                                 comment: "Title of the button that lets users log out of their account")
    }
    
    static func Sign_up_or_log_in() -> String {
        return NSLocalizedString("SIGN_UP_OR_LOG_IN", tableName: nil, bundle: Bundle.main,
                                 value: "Sign Up or Log In",
                                 comment: "Message title informing the user that they must sign up for an account or log in to their account")
    }
    
    static func Sign_up_or_login_to_psicash_account_to_continue() -> String {
        return NSLocalizedString("SIGN_UP_LOG_IN_TO_PSICASH_ACCOUNT_TO_CONTINUE", tableName: nil, bundle: Bundle.main,
                                 value: "Sign Up or Log In to your PsiCash account to continue",
                                 comment: "Do not translate or transliterate 'PsiCash'. Informs the user that they must sign up for a PsiCash account or log in to their PsiCash account in order to user PsiCash features.")
    }
    
    static func Psicash_account() -> String {
        return NSLocalizedString("PSICASH_ACCOUNT", tableName: nil, bundle: Bundle.main,
                                 value: "PsiCash Account",
                                 comment: "Do not translate or transliterate 'PsiCash'. Header of a box providing context that the actions inside the box are related to PsiCash accounts.")
    }
    
    static func Psicash_accounts_last_merge_warning() -> String {
        return NSLocalizedString("PSICASH_ACCOUNTS_LAST_MERGE_WARNING", tableName: nil, bundle: Bundle.main,
                                 value: "Note that this will be the last time that you can merge your PsiCash account.",
                                 comment: "Do not translate or transliterate 'PsiCash'.")
    }
    
    static func Incorrect_username_or_password() -> String {
        return NSLocalizedString("INCORRECT_USERNAME_OR_PASSWORD", tableName: nil, bundle: Bundle.main,
                                 value: "The username or password you entered is incorrect. Please try again.",
                                 comment: "Error message when username or password entered by the user to login into their account is incorrect.")
    }
    
    static func Psicash_logged_in_successfully() -> String {
        return NSLocalizedString("PSICASH_LOGGED_IN_SUCCESSFULLY", tableName: nil, bundle: Bundle.main,
                                 value: "You successfully logged into your PsiCash account.",
                                 comment: "Do not translate or transliterate 'PsiCash'. Alert message when the user has been able to successfully log into their PsiCash account.")
    }
    
    static func Psicash_logged_out_successfully() -> String {
        return NSLocalizedString("PSICASH_LOGGED_OUT_SUCCESSFULLY", tableName: nil, bundle: Bundle.main,
                                 value: "You successfully logged out of your PsiCash account.",
                                 comment: "Do not translate or transliterate 'PsiCash'. Alert message when the user has been able to successfully log out of their PsiCash account.")
    }

    static func Encourage_psicash_account_creation() -> String {
        // TODO: Localize
        return "We strongly encourage you to make a PsiCash account. Having an account allows you to share your balance between devices and protect your purchases."
    }

    static func Continue_without_an_account() -> String {
        // TODO: Localize
        return "Continue without an account"
    }

    static func Create_account() -> String {
        // TODO: Localize
        return "Create account"
    }

    static func Loading() -> String {
        return NSLocalizedString("LOADING", tableName: nil, bundle: Bundle.main,
                                 value: "Loading...",
                                 comment: "Text displayed while app loads")
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

    static func Purchase_failed() -> String {
        return NSLocalizedString("GENERIC_PURCHASE_FAILED", tableName: nil, bundle: Bundle.main,
                                 value: "Purchase Failed",
                                 comment: "Generic alert shown when purchase of a product fails.")
    }
    
    static func Create_your_PsiCash_account() -> String {
        return NSLocalizedString("CREATE_PSICASH_YOUR_ACCOUNT", tableName: nil, bundle: Bundle.main,
                                 value: "Create your PsiCash account",
                                 comment: "Title label next to a button that lets users create a PsiCash account. Do not translate or transliterate 'PsiCash'")
    }
    
    static func Create_new_account_button_title() -> String {
        return NSLocalizedString("CREATE_NEW_ACCOUNT_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Create New Account",
                                 comment: "Button label that lets users create a new account.")
    }
    
    static func Sign_up() -> String {
        return NSLocalizedString("SIGN_UP_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Sign Up",
                                 comment: "Title on a button that lets users sign up for an account")
    }
    
    static func Log_in() -> String {
        return NSLocalizedString("LOG_IN_BUTTON_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Log In",
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
                                 value: "Forgot Password?",
                                 comment: "Button title that lets users reset their password if they forgot their account's password.")
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

    static func Retry_button_title() -> String {
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

// MARK: Feedback upload
extension UserStrings {
    static func Submitted_feedback() -> String {
        return NSLocalizedString("FEEDBACK_UPLOAD_SUCCESSFUL_TITLE", tableName: nil, bundle: Bundle.main,
                                 value: "Thank you for helping improve Psiphon!",
                                 comment: "Alert dialog message thanking the user for helping improve the Psiphon network by submitting their feedback.")
    }
}
