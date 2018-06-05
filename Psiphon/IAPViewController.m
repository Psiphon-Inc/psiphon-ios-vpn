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

#import <PureLayout/ALView+PureLayout.h>
#import "IAPViewController.h"
#import "AppDelegate.h"
#import "IAPStoreHelper.h"
#import "MBProgressHUD.h"
#import "NSDate+Comparator.h"
#import "PsiphonClientCommonLibraryHelpers.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "UIColor+Additions.h"
#import "IAPHelpViewController.h"

static NSString *iapCellID = @"IAPTableCellID";

@interface IAPTableViewCell : UITableViewCell
@end

@interface IAPViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) NSNumberFormatter *priceFormatter;
@property (nonatomic) UIRefreshControl *refreshControl;

@property (nonatomic) UIImage *headerBannerImage;

@property (nonatomic) BOOL hasActiveSubscription;
@property (nonatomic) SKProduct *latestSubscriptionProduct;
@property (nonatomic) NSDate *latestSubscriptionExpirationDate;

@end

@implementation IAPViewController {
    MBProgressHUD *buyProgressAlert;
    NSTimer *buyProgressAlertTimer;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _latestSubscriptionExpirationDate = nil;
        _latestSubscriptionProduct = nil;
        _hasActiveSubscription = FALSE;

        _priceFormatter = [[NSNumberFormatter alloc] init];
        _priceFormatter.formatterBehavior = NSNumberFormatterBehavior10_4;
        _priceFormatter.numberStyle = NSNumberFormatterCurrencyStyle;
    }
    return self;
}

- (void)loadView {

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 70.0;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 0, 0, 0);
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.view = self.tableView;
    
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(startProductsRequest) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];
    [self.tableView sendSubviewToBack:self.refreshControl];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Sets screen background and navigation bar colours.
    self.view.backgroundColor = UIColor.charcoalGreyColor;
    self.navigationController.navigationBar.barTintColor = UIColor.charcoalGreyColor;  // Navigation bar background color
    self.navigationController.navigationBar.tintColor = UIColor.purpleButtonColor;  // Navigation bar items color
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};

    // Sets navigation bar title.
    self.title = NSLocalizedStringWithDefaultValue(@"SUBSCRIPTIONS", nil, [NSBundle mainBundle], @"Subscriptions", @"Title of the dialog for available in-app paid subscriptions");

    // Set back button title of any child view controllers pushed onto the current navigation controller
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringWithDefaultValue(@"BACK_BUTTON", nil, [NSBundle mainBundle], @"Back", @"Title of the button which takes the user to the previous screen. Text should be short and one word when possible.") style:UIBarButtonItemStylePlain target:nil action:nil];

    // Adds "Done" button (dismiss action) to the navigation bar if it is not opened from Setting menu.
    if (!self.openedFromSettings) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                                                  initWithTitle:NSLocalizedStringWithDefaultValue(@"DONE_ACTION", nil, [NSBundle mainBundle], @"Done", @"Title of the button that dismisses the subscriptions menu")
                                                  style:UIBarButtonItemStyleDone
                                                  target:self
                                                  action:@selector(dismissViewController)];
    }

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

    // Initializations based on subscription state.
    if (self.hasActiveSubscription) {
        self.headerBannerImage = [UIImage imageNamed:@"SubscribedBanner"];
    } else {
        self.headerBannerImage = [UIImage imageNamed:@"SubscriptionBanner"];
    }
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

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {

    NSInteger numOfSections = 0;

    if ([[IAPStoreHelper sharedInstance].storeProducts count] > 0) {
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        numOfSections = 1;
        tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, self.tableView.bounds.size.width, 0.01f)];

    } else {
        UITextView *noProductsTextView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, tableView.bounds.size.height)];
        noProductsTextView.backgroundColor = UIColor.charcoalGreyColor;
        noProductsTextView.editable = NO;
        noProductsTextView.font =  [UIFont fontWithName:@"Helvetica" size:15.0f];
        noProductsTextView.textContainerInset = UIEdgeInsetsMake(60, 10, 0, 10);
        noProductsTextView.text = NSLocalizedStringWithDefaultValue(@"NO_PRODUCTS_TEXT", nil, [NSBundle mainBundle],
                                                                    @"Could not retrieve subscriptions from the App Store. Pull to refresh or try again later.",
                                                                    @"Subscriptions view text that is visible when the list of subscriptions is not available");
        noProductsTextView.textColor = UIColor.whiteColor;
        noProductsTextView.textAlignment = NSTextAlignmentCenter;
        tableView.tableHeaderView = noProductsTextView;
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    }
    
    return numOfSections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    NSInteger numRows = 2;  // Start count with number of rows that are always visible.

    if (!self.hasActiveSubscription) {
        numRows += [[IAPStoreHelper sharedInstance].storeProducts count];
    }

    return numRows;
}

#pragma mark - TableView header

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return self.headerBannerImage.size.height;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *cellView = [[UIView alloc] initWithFrame:CGRectZero];

    // Banner image
    UIImageView *banner = [[UIImageView alloc] init];
    banner.translatesAutoresizingMaskIntoConstraints = FALSE;
    banner.contentMode = UIViewContentModeScaleToFill;
    banner.image = self.headerBannerImage;
    [cellView addSubview:banner];

    // Banner label
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, cellView.bounds.size.width, cellView.bounds.size.height)];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textColor = UIColor.whiteColor;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [label.font fontWithSize:18];

    if(self.hasActiveSubscription) {

        label.text = NSLocalizedStringWithDefaultValue(@"ACTIVE_SUBSCRIPTION_SECTION_TITLE",
          nil,
          [NSBundle mainBundle],
          @"You're subscribed!",
          @"Title of the section in the subscription dialog that shows currently active subscription information.");

    } else {
        label.text = NSLocalizedStringWithDefaultValue(@"SUBSCRIPTIONS_PAGE_BANNER_TITLE",
                                                       nil,
                                                       [NSBundle mainBundle],
                                                       @"Get 3 days of premium FREE when subscribing to any plan",
                                                       @"Title of the banner on the subscriptions page that tells the user how many initial free days they get once subscribed");

    }
    [cellView addSubview:label];

    // Header layout constraints
    [banner.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor].active = TRUE;
    [banner.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor].active = TRUE;

    [label.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor constant:10.0].active = TRUE;
    [label.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor constant:10.0].active = TRUE;
    [label.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor].active = TRUE;

    return cellView;
}

#pragma mark - TableView Cells

// Helper method that creates views to add to manage subscription cell.
- (void)createManageSubscriptionCellContent:(UITableViewCell *)cell {
    cell.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    // "Manage your subscription" button
    UIButton *manageSubsButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    manageSubsButton.backgroundColor = UIColor.purpleButtonColor;
    manageSubsButton.layer.cornerRadius = 5.0;
    manageSubsButton.layer.masksToBounds = FALSE;
    manageSubsButton.titleEdgeInsets = UIEdgeInsetsMake(0.0, 24.0, 0.0, 24.0);
    [manageSubsButton setTitle:@"Manage your subscription"
                      forState:UIControlStateNormal];
    [manageSubsButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [manageSubsButton addTarget:self action:@selector(onManageSubscriptionTap) forControlEvents:UIControlEventTouchUpInside];
    [cell.contentView addSubview:manageSubsButton];

    // "Manage your subscription" button constraints
    manageSubsButton.translatesAutoresizingMaskIntoConstraints = FALSE;
    [manageSubsButton.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor].active = TRUE;
    [manageSubsButton.widthAnchor constraintEqualToConstant:250].active = TRUE;
    [manageSubsButton.heightAnchor constraintEqualToConstant:50].active = TRUE;
    [manageSubsButton autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:16.0].active = TRUE;
    if (self.hasActiveSubscription) {
        // Pins manageSubsButton to cell's bottom, since restoreSubsButton will no longer be displayed.
        [manageSubsButton autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:16.0].active = TRUE;
    }

    // Restore subscription button is added if there is no active subscription.
    if (!self.hasActiveSubscription) {
        UIButton *restoreSubsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [restoreSubsButton setTitle:NSLocalizedStringWithDefaultValue(@"SUBSCRIPTIONS_PAGE_RESTORE_SUBSCRIPTION_BUTTON",
                                                                      nil,
                                                                      [NSBundle mainBundle],
                                                                      @"I don't see my subscription",
                                                                      @"Title of the button on the subscriptions page which, when pressed, navigates the user to the page where they can restore their existing subscription")
                           forState:UIControlStateNormal];
        [restoreSubsButton setTitleColor:UIColor.weirdGreenColor forState:UIControlStateNormal];
        [restoreSubsButton addTarget:self action:@selector(onSubscriptionHelpTap) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:restoreSubsButton];

        // Restore subscription button constraints
        restoreSubsButton.translatesAutoresizingMaskIntoConstraints = FALSE;
        [restoreSubsButton.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor].active = TRUE;
        [restoreSubsButton.widthAnchor constraintEqualToConstant:250].active = TRUE;
        [restoreSubsButton.heightAnchor constraintEqualToConstant:30].active = TRUE;
        [restoreSubsButton.topAnchor constraintEqualToAnchor:manageSubsButton.bottomAnchor constant:16.0].active = TRUE;
        [restoreSubsButton autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:16.0].active = TRUE;
    }
}

// Helper method that create subscription detail text
- (void)createDetailTextCellContent:(UITableViewCell *)cell {
    cell.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    label.font = [label.font fontWithSize:15];
    label.textColor = UIColor.whiteColor;
    label.text = NSLocalizedStringWithDefaultValue(@"BUY_SUBSCRIPTIONS_FOOTER_TEXT",
                                                   nil,
                                                   [NSBundle mainBundle],
                                                   @"A subscription is auto-renewable which means that once purchased it will be automatically renewed until you cancel it 24 hours prior to the end of the current period.\n\nYour iTunes Account will be charged for renewal within 24-hours prior to the end of the current period with the cost of the subscription.",
                                                   @"Buy subscription dialog footer text");

    label.textAlignment = NSTextAlignmentLeft;
    [cell.contentView addSubview:label];

    // label constraints
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor].active = TRUE;
    [label autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:16.0].active = TRUE;
    [label autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:16.0].active = TRUE;
    [label autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:16.0].active = TRUE;
    [label autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:16.0].active = TRUE;
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

    IAPTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:iapCellID];
    if (cell == nil) {
        cell = [[IAPTableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:iapCellID];
        cell.backgroundColor = UIColor.clearColor;
    }
    SKProduct * product = (SKProduct *) [IAPStoreHelper sharedInstance].storeProducts[indexPath.row];
    [self.priceFormatter setLocale:product.priceLocale];
    NSString *localizedPrice = [self.priceFormatter stringFromNumber:product.price];
    cell.textLabel.text = product.localizedTitle;
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.detailTextLabel.text = product.localizedDescription;
    cell.detailTextLabel.textColor = UIColor.whiteColor;

    if(self.hasActiveSubscription) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
        cell.accessoryView = nil;
        cell.textLabel.text = self.latestSubscriptionProduct.localizedTitle;
        cell.detailTextLabel.text = @"";
    } else {
        UISegmentedControl *buyButton = [[UISegmentedControl alloc]initWithItems:[NSArray arrayWithObject:localizedPrice]];
        buyButton.momentary = YES;
        buyButton.tag = indexPath.row;
        [buyButton addTarget:self
                      action:@selector(buyButtonPressed:)
            forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = buyButton;
    }

    return cell;
}

#pragma mark - Footer

- (nullable UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {

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
    privacyPolicyButton.titleLabel.font = [UIFont systemFontOfSize:14];
    privacyPolicyButton.titleLabel.numberOfLines = 0;
    [privacyPolicyButton setTitleColor:UIColor.weirdGreenColor forState:UIControlStateNormal];
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
    tosButton.titleLabel.font = [UIFont systemFontOfSize:14];
    tosButton.titleLabel.numberOfLines = 0;
    [tosButton setTitleColor:UIColor.weirdGreenColor forState:UIControlStateNormal];
    [terms addSubview:tosButton];


    // Layout constraints
    terms.translatesAutoresizingMaskIntoConstraints = NO;
    tosButton.translatesAutoresizingMaskIntoConstraints = NO;
    privacyPolicyButton.translatesAutoresizingMaskIntoConstraints = NO;

    [terms.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor].active = TRUE;
    [terms autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:16.0].active = TRUE;
    [terms autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:16.0].active = TRUE;
    [terms autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:16.0].active = TRUE;
    [terms autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:16.0].active = TRUE;

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
    [self endRefreshingUI];
    [self updateHasActiveSubscription];
    [self.tableView reloadData];
}

- (void)startProductsRequest {
    [self beginRefreshingUI];
    [[IAPStoreHelper sharedInstance] startProductsRequest];
}

- (void)onPaymentTransactionUpdate:(NSNotification *)notification {
    SKPaymentTransactionState transactionState = (SKPaymentTransactionState) [notification.userInfo[IAPHelperPaymentTransactionUpdateKey] integerValue];

    if (SKPaymentTransactionStatePurchasing == transactionState) {
        [self showProgressSpinnerAndBlockUI];
        [self setPurchaseButtonUIInterface:FALSE];
    } else {
        [self dismissProgressSpinnerAndUnblockUI];
        [self setPurchaseButtonUIInterface:TRUE];
    }
}

- (void)showProgressSpinnerAndBlockUI {
    if (buyProgressAlert != nil) {
        [buyProgressAlert hideAnimated:YES];
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

- (void)setPurchaseButtonUIInterface:(BOOL)interactionEnabled {
    NSInteger numSections = [self.tableView numberOfSections];

    if (numSections == 1) {

        NSInteger numRows = [self.tableView numberOfRowsInSection:0];

        for (NSInteger i = 0; i < numRows; i++) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]];

            if (cell.accessoryView
              && [cell.accessoryView isKindOfClass:[UISegmentedControl class]]
              && [cell isKindOfClass:[IAPTableViewCell class]]) {

                UISegmentedControl *buyButton = (UISegmentedControl *) cell.accessoryView;

                if (interactionEnabled) {
                    [buyButton setTintColor:self.view.tintColor];
                } else {
                    [buyButton setTintColor:UIColor.grayColor];
                }
                
                buyButton.userInteractionEnabled = interactionEnabled;
            }
        }
    }
}

- (void)updateHasActiveSubscription {
    // Load subscription information.
    if ([IAPStoreHelper hasActiveSubscriptionForNow]) {

        // Store latest product expiration date.
        self.latestSubscriptionExpirationDate = IAPStoreHelper.subscriptionDictionary[kLatestExpirationDate];

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

#pragma mark - IAPTableViewCell auto resizable cell implementation

@implementation IAPTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
        self.textLabel.numberOfLines = 0;
        self.textLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
        self.detailTextLabel.numberOfLines = 0;
        self.detailTextLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.detailTextLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.3];
        
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[textLabel]-|" options:0 metrics:nil views:@{ @"textLabel": self.textLabel}]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[detailTextLabel]-|" options:0 metrics:nil views:@{ @"detailTextLabel": self.detailTextLabel}]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[textLabel][detailTextLabel]-|" options:0 metrics:nil views:@{ @"textLabel": self.textLabel, @"detailTextLabel": self.detailTextLabel}]];
    }
    
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self.contentView setNeedsLayout];
    [self.contentView layoutIfNeeded];
    self.textLabel.preferredMaxLayoutWidth = CGRectGetWidth(self.textLabel.frame);
}

@end
