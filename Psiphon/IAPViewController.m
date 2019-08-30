/*
 * Copyright (c) 2017, Psiphon Inc.
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

#import "IAPViewController.h"
#import "AppDelegate.h"
#import "IAPStoreHelper.h"
#import "MBProgressHUD.h"
#import "NSDate+Comparator.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "IAPHelpViewController.h"
#import "UIColor+Additions.h"
#import "UIFont+Additions.h"
#import "Strings.h"
#import "Logging.h"
#import "BorderedSubtitleButton.h"
#import "CloudsView.h"
#import "UIView+Additions.h"
#import "RoyalSkyButton.h"
#import "DispatchUtils.h"
#import "Nullity.h"

// Ratio of the width of table view cell's content to the cell.
#define CellContentWithMultiplier 0.88

static NSString *iapCellID = @"IAPTableCellID";

@interface IAPViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) NSNumberFormatter *priceFormatter;
@property (nonatomic) UIRefreshControl *refreshControl;

@property (nonatomic) BOOL hasActiveSubscription;
@property (nonatomic) BOOL hasBeenInIntroPeriod;
@property (nonatomic) SKProduct *latestSubscriptionProduct;
@property (nonatomic) NSDate *latestSubscriptionExpirationDate;

@end

@implementation IAPViewController {
    MBProgressHUD *buyProgressAlert;
    NSTimer *buyProgressAlertTimer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _latestSubscriptionExpirationDate = nil;
        _latestSubscriptionProduct = nil;
        _hasActiveSubscription = FALSE;
        _hasBeenInIntroPeriod = FALSE;

        _priceFormatter = [[NSNumberFormatter alloc] init];
        _priceFormatter.formatterBehavior = NSNumberFormatterBehavior10_4;
        _priceFormatter.numberStyle = NSNumberFormatterCurrencyStyle;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Removes the default iOS bottom border.
    [self.navigationController.navigationBar setValue:@(TRUE) forKeyPath:@"hidesShadow"];

    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.barTintColor = UIColor.darkBlueColor;
    self.navigationController.navigationBar.translucent = FALSE;

    self.navigationController.navigationBar.titleTextAttributes = @{
      NSForegroundColorAttributeName:UIColor.blueGreyColor,
      NSFontAttributeName:[UIFont avenirNextBold:15.f]
    };

    // Sets navigation bar title.
    NSString *title = NSLocalizedStringWithDefaultValue(@"SUBSCRIPTIONS", nil, [NSBundle mainBundle], @"Subscriptions", @"Title of the dialog for available in-app paid subscriptions");
    self.title = title.localizedUppercaseString;

    // Set back button title of any child view controllers pushed onto the current navigation controller
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringWithDefaultValue(@"BACK_BUTTON", nil, [NSBundle mainBundle], @"Back", @"Title of the button which takes the user to the previous screen. Text should be short and one word when possible.") style:UIBarButtonItemStylePlain target:nil action:nil];

    // Adds "Done" button (dismiss action) to the navigation bar if it is not opened from Setting menu.
    if (!self.openedFromSettings) {
        UIBarButtonItem *doneButton = [[UIBarButtonItem alloc]
          initWithTitle:NSLocalizedStringWithDefaultValue(@"DONE_ACTION", nil, [NSBundle mainBundle], @"Done", @"Title of the button that dismisses the subscriptions menu")
                  style:UIBarButtonItemStyleDone
                 target:self
                 action:@selector(dismissViewController)];
        doneButton.tintColor = UIColor.whiteColor;

        self.navigationItem.rightBarButtonItem = doneButton;

    }

    // Setup CloudView
    CloudsView *cloudBackgroundView = [[CloudsView alloc] initForAutoLayout];
    [self.view addSubview: cloudBackgroundView];
    [NSLayoutConstraint activateConstraints:@[
        [cloudBackgroundView.topAnchor constraintEqualToAnchor:self.view.safeTopAnchor],
        [cloudBackgroundView.bottomAnchor constraintEqualToAnchor:self.view.safeBottomAnchor],
        [cloudBackgroundView.leadingAnchor constraintEqualToAnchor:self.view.safeLeadingAnchor],
        [cloudBackgroundView.trailingAnchor constraintEqualToAnchor:self.view.safeTrailingAnchor],
    ]];

    // Setup TableView
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 100.0; // If not set, header is not shown on iOS 10.x
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 70.0;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 0, 0, 0);
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];


    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(startProductsRequest) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];
    [self.tableView sendSubviewToBack:self.refreshControl];

    // Sets screen background and navigation bar colours.
    self.view.backgroundColor = UIColor.darkBlueColor;

    // Sets auto layout for the TableView
    self.tableView.translatesAutoresizingMaskIntoConstraints = FALSE;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeTopAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeBottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.safeLeadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.safeTrailingAnchor],
    ]];

    // Listens to IAPStoreHelper transaction states.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPaymentTransactionUpdate:)
                                                 name:IAPHelperPaymentTransactionUpdateNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProducts)
                                                 name:IAPSKProductsRequestDidFailWithErrorNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProducts)
                                                 name:IAPSKProductsRequestDidReceiveResponseNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProducts)
                                                 name:IAPSKRequestRequestDidFinishNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProducts)
                                                 name:IAPHelperUpdatedSubscriptionDictionaryNotification
                                               object:nil];

    [self updateHasActiveSubscription];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if([[IAPStoreHelper sharedInstance].storeProducts count] == 0) {
        // retry getting products from the store
        [self startProductsRequest];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if ([self isMovingFromParentViewController]) {
        self.navigationController.navigationBar.barStyle = UIBarStyleDefault;
    }
}

#pragma mark - Table view data source

- (UIView *)createNoProductsView {
    UIView *stack = [[UIView alloc] initWithFrame:CGRectZero];

    UILabel *noProductsLabel = [[UILabel alloc] init];
    noProductsLabel.numberOfLines = 0;
    noProductsLabel.lineBreakMode = NSLineBreakByWordWrapping;
    noProductsLabel.textColor = UIColor.whiteColor;
    noProductsLabel.textAlignment = NSTextAlignmentCenter;
    noProductsLabel.font = [UIFont avenirNextDemiBold:14.0];
    noProductsLabel.text = Strings.productRequestFailedNoticeText;

    UIButton *refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    NSString *refreshButtonTitle = @"Tap to retry".localizedUppercaseString;
    [refreshButton setTitle:refreshButtonTitle forState:UIControlStateNormal];
    [refreshButton setTitle:refreshButtonTitle forState:UIControlStateHighlighted];
    [refreshButton setTintColor:UIColor.whiteColor];
    refreshButton.titleLabel.font = [UIFont avenirNextDemiBold:14.0];
    [refreshButton addTarget:self
                      action:@selector(startProductsRequest)
            forControlEvents:UIControlEventTouchUpInside];

    // Add subview to the stack view.
    [stack addSubview:noProductsLabel];
    [stack addSubview:refreshButton];

    // Setup layout constraints
    noProductsLabel.translatesAutoresizingMaskIntoConstraints = FALSE;
    refreshButton.translatesAutoresizingMaskIntoConstraints = FALSE;

    [NSLayoutConstraint activateConstraints:@[
        [noProductsLabel.topAnchor constraintEqualToAnchor:stack.topAnchor constant:50.0],
        [noProductsLabel.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor],
        [noProductsLabel.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor],
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [refreshButton.topAnchor constraintEqualToAnchor:noProductsLabel.bottomAnchor
                                                constant:20.0],
        [refreshButton.centerXAnchor constraintEqualToAnchor:stack.centerXAnchor],
        [refreshButton.bottomAnchor constraintEqualToAnchor:stack.bottomAnchor],
    ]];

    return stack;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    if ([[IAPStoreHelper sharedInstance].storeProducts count] == 0) {
        return 0;
    }

    NSInteger numRows = 2;  // Start count with number of rows that are always visible.

    if (!self.hasActiveSubscription) {
        numRows += [[IAPStoreHelper sharedInstance].storeProducts count];
    }

    return numRows;
}

#pragma mark - TableView header

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {

    // If no products have been loaded show the alternative header.
    if ([[IAPStoreHelper sharedInstance].storeProducts count] == 0) {
        UIView *header = [self createNoProductsView];
        return header;

    } else {
        UIView *cellView = [[UIView alloc] initWithFrame:CGRectZero];

        // Banner Title
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
        title.numberOfLines = 0;
        title.lineBreakMode = NSLineBreakByWordWrapping;
        title.textColor = UIColor.whiteColor;
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont avenirNextDemiBold:22.0];

        // Banner subtitle
        UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectZero];
        subtitle.numberOfLines = 0;
        subtitle.lineBreakMode = NSLineBreakByWordWrapping;
        subtitle.textColor = UIColor.blueGreyColor;
        subtitle.textAlignment = NSTextAlignmentCenter;
        subtitle.font = [UIFont avenirNextDemiBold:13.0];

        if(self.hasActiveSubscription) {
            title.text = Strings.activeSubscriptionBannerTitle;
            subtitle.hidden = TRUE;
        } else {
            title.text = Strings.inactiveSubscriptionBannerTitle;
            subtitle.text = Strings.inactiveSubscriptionBannerSubtitle;
        }

        [cellView addSubview:title];
        [cellView addSubview:subtitle];

        // Label layout constraints
        title.translatesAutoresizingMaskIntoConstraints = FALSE;
        subtitle.translatesAutoresizingMaskIntoConstraints = FALSE;

        [NSLayoutConstraint activateConstraints:@[
            [title.topAnchor constraintEqualToAnchor:cellView.topAnchor constant:35.0],
            [title.centerXAnchor constraintEqualToAnchor:cellView.centerXAnchor],

            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:18.0],
            [subtitle.centerXAnchor constraintEqualToAnchor:cellView.centerXAnchor],
            [subtitle.bottomAnchor constraintEqualToAnchor:cellView.bottomAnchor constant:-20.0]
        ]];

        return cellView;
    }
}

#pragma mark - TableView Cells

- (BorderedSubtitleButton *)createSubscriptionButtonForProduct:(SKProduct *)product {
    BorderedSubtitleButton *button = [[BorderedSubtitleButton alloc] initForAutoLayout];
    button.shadow = TRUE;
    button.subtitleLabel.font = [UIFont avenirNextDemiBold:13.0];

    // Generates button's labels texts.
    CGFloat titleFontSize = 16.0;
    NSDictionary *boldFontAttribute = @{NSFontAttributeName: [UIFont avenirNextBold:titleFontSize]};
    NSDictionary *regularFontAttribute = @{NSFontAttributeName: [UIFont avenirNextDemiBold:titleFontSize]};

    [self.priceFormatter setLocale:product.priceLocale];

    NSString *localizedPrice = [self.priceFormatter stringFromNumber:product.price];
    NSAttributedString *titlePriceString = [[NSAttributedString alloc]
                                       initWithString:localizedPrice
                                       attributes:boldFontAttribute];

    // Modify subscription period since 1 week is translated as 7 days

    NSString *periodString;
    if (@available(iOS 11.2, *)) {
        periodString = [NSString stringWithFormat:@" / %@",
                        [StringUtils stringForSubscriptionPeriod:product.subscriptionPeriod
                                             dropNumOfUnitsIfOne:TRUE
                                                   andAbbreviate:FALSE]];

    } else {
        // Fallback on earlier versions
        periodString = [NSString stringWithFormat:@" - %@", product.localizedTitle];
    }
    NSAttributedString *titlePeriodString = [[NSMutableAttributedString alloc]
                                             initWithString:periodString
                                             attributes:regularFontAttribute];

    NSMutableAttributedString *titleString = [[NSMutableAttributedString alloc] init];
    [titleString appendAttributedString:titlePriceString];
    [titleString appendAttributedString:titlePeriodString];

    NSString *subtitleString = @"";
    if (@available(iOS 11.2, *)) {

        // Nil, if this product doesn't have a discount offer.
        SKProductDiscount *_Nullable discount = product.introductoryPrice;

        // Shows intro offer based on user's eligiblity.
        if (discount != nil && !self.hasBeenInIntroPeriod) {

            NSString *discPrice = [self.priceFormatter stringFromNumber:discount.price];

            // Example: "Week", "6 Months", "2 Years"
            NSString *regularUnit = [StringUtils
                                     stringForSubscriptionPeriod:product.subscriptionPeriod
                                     dropNumOfUnitsIfOne:TRUE
                                     andAbbreviate:TRUE];

            switch (discount.paymentMode) {
                // Example: "$6.49/mo. for the first 5 months, $12.99/mo. after"
                //          "$2.99/2 mos. for the first 6 months, $14.99/2 mos. after"
                case SKProductDiscountPaymentModePayAsYouGo: {

                    // Example: "Weeks", "Months", ... based on whether `discount.numberOfPeriods` > 1.
                    NSString *periodUnitString = [StringUtils
                                                  stringForPeriodUnit:discount.subscriptionPeriod.unit
                                                  pluralGivenUnits:discount.numberOfPeriods
                                                  andAbbreviate:FALSE];

                    // Example: If subscriptionPeriod.numberOfUnits is 2 (e.g. $1/2 Month)
                    // and the offer duration is for 6 months, then `discount.numberOfPeriods` is 3.
                    // So the total duration is:
                    // `subsriptionPeriod.numberOfUnits * discount.numberOfPeriods`.
                    NSUInteger totalDiscDuration = discount.numberOfPeriods * discount.subscriptionPeriod.numberOfUnits;

                    // Example: "Week", "6 Months", "2 Years"
                    NSString *discPeriodDenom = [StringUtils
                                                 stringForSubscriptionPeriod:discount.subscriptionPeriod
                                                 dropNumOfUnitsIfOne:TRUE
                                                 andAbbreviate:TRUE];

                    subtitleString = [NSString
                                      stringWithFormat:@"%@/%@ for the first %lu %@, %@/%@ after",
                                      discPrice, discPeriodDenom, (unsigned long)totalDiscDuration,
                                      periodUnitString, localizedPrice, regularUnit];
                    break;
                }
                // Example: "$9.99 for the first 6 months, $124.99/yr. after"
                //          "$49.99 for the first year, $99.99/yr. after"
                case SKProductDiscountPaymentModePayUpFront: {

                    // Example: "Week", "6 Months", "2 Years"
                    NSString *discPeriodDropOne = [StringUtils
                                            stringForSubscriptionPeriod:discount.subscriptionPeriod
                                            dropNumOfUnitsIfOne:TRUE
                                            andAbbreviate:FALSE];

                    subtitleString = [NSString
                                      stringWithFormat:@"%@ for the first %@, %@/%@ after",
                                      discPrice, discPeriodDropOne, localizedPrice, regularUnit];
                    break;
                }
                // Example: "3 days of free trial, $2.99/wk. after"
                case SKProductDiscountPaymentModeFreeTrial: {

                    // Example: "1 Week", "6 Months", "2 Years"
                    NSString *discPeriodFull = [StringUtils
                                            stringForSubscriptionPeriod:discount.subscriptionPeriod
                                            dropNumOfUnitsIfOne:FALSE
                                            andAbbreviate:FALSE];

                    subtitleString = [NSString
                                      stringWithFormat:@"%@ of free trial, %@/%@ after",
                                      discPeriodFull, localizedPrice, regularUnit];
                    break;
                }
            }

            subtitleString = subtitleString.localizedLowercaseString;

        }
    } else {
        // Fallback for older devices.
        subtitleString = product.localizedDescription;
    }

    // Sets the button's labels texts.
    button.titleLabel.attributedText = titleString;

    // Remove subtitle label if there is no text to be displayed.
    if ([Nullity isEmpty:subtitleString]) {
        [button removeSubtitleLabel];
    } else {
        button.subtitleLabel.text = subtitleString;
    }

    return button;
}

// Helper method that creates views to add to manage subscription cell.
- (void)createManageSubscriptionCellContent:(UITableViewCell *)cell {

    cell.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    // "Manage your subscription" button
    RoyalSkyButton *manageSubsButton = [[RoyalSkyButton alloc] initForAutoLayout];
    [manageSubsButton setFontSize:16.0];
    [manageSubsButton setTitle:Strings.manageYourSubscriptionButtonTitle];
    [manageSubsButton addTarget:self action:@selector(onManageSubscriptionTap) forControlEvents:UIControlEventTouchUpInside];
    [cell.contentView addSubview:manageSubsButton];

    // "Manage your subscription" button constraints
    manageSubsButton.translatesAutoresizingMaskIntoConstraints = FALSE;
    [NSLayoutConstraint activateConstraints:@[
        [manageSubsButton.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:16.0],
        [manageSubsButton.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
        [manageSubsButton.heightAnchor constraintEqualToConstant:50],
        [manageSubsButton.widthAnchor constraintEqualToAnchor:cell.contentView.widthAnchor
                                                   multiplier:CellContentWithMultiplier],
    ]];

    if (self.hasActiveSubscription) {
        // Pins manageSubsButton to cell's bottom, since restoreSubsButton will no longer be displayed.
        [manageSubsButton.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor
                                                      constant:-16.f].active = TRUE;
    }

    // Restore subscription button is added if there is no active subscription.
    if (!self.hasActiveSubscription) {
        UIButton *restoreSubsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [restoreSubsButton setTitle:Strings.iDontSeeMySubscriptionButtonTitle
                           forState:UIControlStateNormal];
        [restoreSubsButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        restoreSubsButton.titleLabel.font = [UIFont avenirNextDemiBold:16.f];
        [restoreSubsButton addTarget:self action:@selector(onSubscriptionHelpTap) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:restoreSubsButton];

        // Restore subscription button constraints
        restoreSubsButton.translatesAutoresizingMaskIntoConstraints = FALSE;

        [NSLayoutConstraint activateConstraints:@[
            [restoreSubsButton.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
            [restoreSubsButton.heightAnchor constraintEqualToConstant:30],
            [restoreSubsButton.topAnchor constraintEqualToAnchor:manageSubsButton.bottomAnchor
                                                        constant:16.0],
            [restoreSubsButton.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor
                                                           constant:-16.f],
            [restoreSubsButton.widthAnchor constraintEqualToAnchor:cell.contentView.widthAnchor
                                                        multiplier:CellContentWithMultiplier],
        ]];

    }
}

// Helper method that create subscription detail text
- (void)createDetailTextCellContent:(UITableViewCell *)cell {
    cell.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    label.font = [UIFont avenirNextMedium:15.f];
    label.textColor = UIColor.blueGreyColor;
    label.text = [NSString stringWithFormat:@"%@\n\n%@", Strings.subscriptionScreenNoticeText, Strings.subscriptionScreenCancelNoticeText];
    [cell.contentView addSubview:label];

    // label constraints
    label.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
        [label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor
                                        constant:16.f],
        [label.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor
                                           constant:-16.f],
        [label.widthAnchor constraintEqualToAnchor:cell.contentView.widthAnchor
                                        multiplier:CellContentWithMultiplier],
    ]];

}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    NSInteger numRows = [tableView numberOfRowsInSection:0];

    // If index is at the third last row, adds the "Manage subscription" button.
    if (indexPath.row == numRows - 2) {

        // Manage subscription cell (contains manage subscription and subscription restore buttons).
        UITableViewCell *cell = [[UITableViewCell alloc] init];
        [self createManageSubscriptionCellContent:cell];
        return cell;
    }

    // If index is at the second last row, add subscription detail text
    if (indexPath.row == numRows - 1) {
        UITableViewCell *cell = [[UITableViewCell alloc] init];
        [self createDetailTextCellContent:cell];
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] init];
    if (!self.hasActiveSubscription) {
        
        SKProduct *product = [IAPStoreHelper sharedInstance].storeProducts[indexPath.row];

        cell.backgroundColor = UIColor.clearColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        BorderedSubtitleButton *button = [self createSubscriptionButtonForProduct:product];
        [button addTarget:self
                   action:@selector(buyButtonPressed:)
         forControlEvents:UIControlEventTouchUpInside];

        button.tag = indexPath.row; // Tag is used to determine which product is selected.

        button.translatesAutoresizingMaskIntoConstraints = FALSE;
        [cell.contentView addSubview:button];


        [NSLayoutConstraint activateConstraints:@[
            [button.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:7.0],
            [button.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-7.0],
            [button.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
            [button.widthAnchor constraintEqualToAnchor:cell.contentView.widthAnchor
                                             multiplier:CellContentWithMultiplier],
        ]];

    }

    return cell;
}

#pragma mark - Footer

- (nullable UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {

    // Does not show the regular footer if no products have been loaded.
    if ([[IAPStoreHelper sharedInstance].storeProducts count] == 0) {
        return nil;
    }

    UIView *cell = [[UIView alloc] initWithFrame:CGRectZero];

    cell.backgroundColor = UIColor.clearColor;

    UIView *terms = [[UIView alloc] init];
    [cell addSubview:terms];

    UIButton *privacyPolicyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [privacyPolicyButton addTarget:self action:@selector(openPrivacyPolicy) forControlEvents:UIControlEventTouchUpInside];
    [privacyPolicyButton setTitle:NSLocalizedStringWithDefaultValue(@"SUBSCRIPTIONS_PRIVACY_POLICY_BUTTON_TEXT",
        nil,
        [NSBundle mainBundle],
        @"Privacy Policy",
        @"Title of button on subscriptions page which opens Psiphon's privacy policy webpage")
                         forState:UIControlStateNormal];
    privacyPolicyButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    privacyPolicyButton.titleLabel.font = [UIFont avenirNextDemiBold:14.f];
    privacyPolicyButton.titleLabel.numberOfLines = 0;
    [privacyPolicyButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [terms addSubview:privacyPolicyButton];

    UIButton *tosButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [tosButton addTarget:self action:@selector(openToS) forControlEvents:UIControlEventTouchUpInside];

    [tosButton setTitle:NSLocalizedStringWithDefaultValue(@"SUBSCRIPTIONS_TERMS_OF_USE_BUTTON_TEXT",
        nil,
        [NSBundle mainBundle],
        @"Terms of Use",
        @"Title of button on subscriptions page which opens Psiphon's terms of use webpage")
               forState:UIControlStateNormal];
    tosButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    tosButton.titleLabel.font = [UIFont avenirNextDemiBold:14.f];
    tosButton.titleLabel.numberOfLines = 0;
    [tosButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [terms addSubview:tosButton];

    // Layout constraints
    terms.translatesAutoresizingMaskIntoConstraints = NO;
    tosButton.translatesAutoresizingMaskIntoConstraints = NO;
    privacyPolicyButton.translatesAutoresizingMaskIntoConstraints = NO;

    [terms.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor].active = TRUE;
    [terms.topAnchor constraintEqualToAnchor:cell.topAnchor
                                    constant:20.f].active = TRUE;
    [terms.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor
                                       constant:-16.f].active = TRUE;
    [terms.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor
                                        constant:16.f].active = TRUE;
    [terms.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor
                                         constant:-16.f].active = TRUE;

    [privacyPolicyButton.heightAnchor constraintEqualToAnchor:terms.heightAnchor].active = YES;
    [privacyPolicyButton.centerYAnchor constraintEqualToAnchor:terms.centerYAnchor].active = YES;
    [privacyPolicyButton.leadingAnchor constraintEqualToAnchor:terms.leadingAnchor].active = YES;
    [privacyPolicyButton.trailingAnchor constraintEqualToAnchor:terms.centerXAnchor].active = YES;

    [tosButton.heightAnchor constraintEqualToAnchor:terms.heightAnchor].active = YES;
    [tosButton.centerYAnchor constraintEqualToAnchor:terms.centerYAnchor].active = YES;
    [tosButton.leadingAnchor constraintEqualToAnchor:terms.centerXAnchor].active = YES;
    [tosButton.trailingAnchor constraintEqualToAnchor:terms.trailingAnchor].active = YES;

    return cell;
}

#pragma mark -

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return NO;
}

// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the item to be re-orderable.
    return NO;
}

#pragma mark -

- (void)buyButtonPressed:(UISegmentedControl *)sender {
    int productID = (int)sender.tag;

    [self showProgressSpinnerAndBlockUI];

    if([IAPStoreHelper sharedInstance].storeProducts.count > productID) {
        SKProduct* product = [IAPStoreHelper sharedInstance].storeProducts[productID];
        [[IAPStoreHelper sharedInstance] buyProduct:product];
    }
}

- (void)openURL:(NSURL*)url {
    if (url != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Not officially documented by Apple, however a runtime warning is generated sometimes
            // stating that [UIApplication openURL:options:completionHandler:] must be used from
            // the main thread only.
            [[UIApplication sharedApplication] openURL:url
                                               options:@{}
                                     completionHandler:nil];
        });
    }
}

- (void)openPrivacyPolicy {
    NSURL *url = [NSURL URLWithString:NSLocalizedStringWithDefaultValue(@"PRIVACY_POLICY_URL", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"https://psiphon.ca/en/privacy.html", @"External link to the privacy policy page. Please update this with the correct language specific link (if available) e.g. https://psiphon.ca/fr/privacy.html for french.")];
    [self openURL:url];
}

- (void)openToS {
    NSURL *url = [NSURL URLWithString:NSLocalizedStringWithDefaultValue(@"LICENSE_PAGE_URL", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"https://psiphon.ca/en/license.html", "External link to the license page. Please update this with the correct language specific link (if available) e.g. https://psiphon.ca/fr/license.html for french.")];
    [self openURL:url];
}

- (void)onManageSubscriptionTap {
    // Apple docs: https://developer.apple.com/library/content/documentation/NetworkingInternet/Conceptual/StoreKitGuide/Chapters/Subscriptions.html#//apple_ref/doc/uid/TP40008267-CH7-SW6
    // Using "itmss" protocol to open iTunes directly. https://stackoverflow.com/a/18135776
    // If the iTunes app is uninstalled, the system will show a "Restore iTunes Store" dialog, this behaviour is the same
    // whether the "itmss" protocol is used or not.
    [self openURL:[NSURL URLWithString:@"itmss://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/manageSubscriptions"]];
}

- (void)onSubscriptionHelpTap {
    IAPHelpViewController *vc = [[IAPHelpViewController alloc]init];
    [self.navigationController pushViewController:vc animated:TRUE];
}

- (void)beginRefreshingUI {
    if (!self.refreshControl.isRefreshing) {
        [self.refreshControl beginRefreshing];
        [self.tableView setContentOffset:CGPointMake(0, self.tableView.contentOffset.y-self.refreshControl.frame.size.height) animated:YES];
    }

    // Timeout after 20 seconds
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self endRefreshingUI];
    });
}

- (void)endRefreshingUI {
    if (self.refreshControl.isRefreshing) {
        [self.refreshControl endRefreshing];
    }
}

- (void)dismissViewController {
    if (self.openedFromSettings) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)reloadProducts {
    dispatch_async_main(^{
        [self endRefreshingUI];
        [self updateHasActiveSubscription];
        [self.tableView reloadData];
    });
}

- (void)startProductsRequest {
    [self beginRefreshingUI];
    [[IAPStoreHelper sharedInstance] startProductsRequest];
}

- (void)onPaymentTransactionUpdate:(NSNotification *)notification {
    SKPaymentTransactionState transactionState = (SKPaymentTransactionState) [notification.userInfo[IAPHelperPaymentTransactionUpdateKey] integerValue];

    if (SKPaymentTransactionStatePurchasing == transactionState) {
        [self showProgressSpinnerAndBlockUI];
    } else {
        [self dismissProgressSpinnerAndUnblockUI];
    }
}

- (void)showProgressSpinnerAndBlockUI {
    if (buyProgressAlert != nil) {
        return;
    }
    buyProgressAlert = [MBProgressHUD showHUDAddedTo:AppDelegate.getTopMostViewController.view animated:YES];

    buyProgressAlertTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:NO block:^(NSTimer * _Nonnull timer) {
        if (buyProgressAlert  != nil) {
            [buyProgressAlert.button setTitle:NSLocalizedStringWithDefaultValue(@"BUY_REQUEST_PROGRESS_ALERT_DISMISS_BUTTON_TITLE", nil, [NSBundle mainBundle], @"Dismiss", @"Title of button on alert view which shows the progress of the user's buy request. Hitting this button dismisses the alert and the buy request continues processing in the background.") forState:UIControlStateNormal];
            [buyProgressAlert.button addTarget:self action:@selector(dismissProgressSpinnerAndUnblockUI) forControlEvents:UIControlEventTouchUpInside];
        }
    }];
}

- (void)dismissProgressSpinnerAndUnblockUI {
    if (buyProgressAlertTimer != nil) {
        [buyProgressAlertTimer invalidate];
        buyProgressAlertTimer = nil;
    }
    if (buyProgressAlert != nil) {
        [buyProgressAlert hideAnimated:YES];
        buyProgressAlert = nil;
    }
}

- (void)updateHasActiveSubscription {
    // Load subscription information.
    if ([IAPStoreHelper hasActiveSubscriptionForNow]) {

        // Store latest product expiration date.
        self.latestSubscriptionExpirationDate = IAPStoreHelper.subscriptionDictionary[kLatestExpirationDate];
        self.hasBeenInIntroPeriod = [IAPStoreHelper.subscriptionDictionary[kHasBeenInIntroPeriod] boolValue];

        NSString *productId = IAPStoreHelper.subscriptionDictionary[kProductId];

        for (SKProduct *product in [IAPStoreHelper sharedInstance].storeProducts) {
            if ([product.productIdentifier isEqualToString:productId]) {
                self.latestSubscriptionProduct = product;
                self.hasActiveSubscription = TRUE;

                break;
            }
        }
    }
}

@end
