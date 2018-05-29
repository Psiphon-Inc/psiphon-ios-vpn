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

static NSString *iapCellID = @"IAPTableCellID";

@interface IAPTableViewCell : UITableViewCell
@end

@interface IAPViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSNumberFormatter *priceFormatter;
@property (nonatomic, strong) UIRefreshControl *refreshControl;

@property (nonatomic, assign) BOOL hasActiveSubscription;
@property (nonatomic, strong) SKProduct *latestSubscriptionProduct;
@property (nonatomic, strong) NSDate *latestSubscriptionExpirationDate;

@property (nonatomic, strong) UIColor *buyButtonTintColor;

@end

@implementation IAPViewController {
    MBProgressHUD *buyProgressAlert;
    NSTimer *buyProgressAlertTimer;
}

- (void)loadView {
    self.priceFormatter = [[NSNumberFormatter alloc] init];
    self.priceFormatter.formatterBehavior = NSNumberFormatterBehavior10_4;
    self.priceFormatter.numberStyle = NSNumberFormatterCurrencyStyle;
    
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
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
    
    NSString* title = NSLocalizedStringWithDefaultValue(@"SUBSCRIPTIONS", nil, [NSBundle mainBundle], @"Subscriptions", @"Title of the dialog for available in-app paid subscriptions");
    self.title = title;
    
    if (!_openedFromSettings) {
        NSString* rightButtonTitle = NSLocalizedStringWithDefaultValue(@"DONE_ACTION", nil, [NSBundle mainBundle], @"Done", @"Title of the button that dismisses the subscriptions menu");
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                                                  initWithTitle:rightButtonTitle
                                                  style:UIBarButtonItemStyleDone
                                                  target:self
                                                  action:@selector(dismissViewController)];
    }

    // Listens to IAPStoreHelper transaction states.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPaymentTransactionUpdate:)
                                                 name:IAPHelperPaymentTransactionUpdateNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if([[IAPStoreHelper sharedInstance].storeProducts count] == 0) {
        // retry getting products from the store
        [self startProductsRequest];
    }

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
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // Check if there's an active subscription and store metadata
    NSDictionary *subscriptionDictionary = [[IAPStoreHelper class] subscriptionDictionary];
    self.latestSubscriptionExpirationDate = nil;
    self.hasActiveSubscription = NO;
    self.latestSubscriptionProduct = nil;

    if(subscriptionDictionary && [subscriptionDictionary isKindOfClass:[NSDictionary class]]) {
        self.latestSubscriptionExpirationDate = subscriptionDictionary[kLatestExpirationDate];
        if(self.latestSubscriptionExpirationDate) {
            NSDate *currentDate = [NSDate date];
            if ([currentDate beforeOrEqualTo:self.latestSubscriptionExpirationDate]) {
                NSString *productID = subscriptionDictionary[kProductId];

                for (SKProduct *product in [IAPStoreHelper sharedInstance].storeProducts) {
                    if ([product.productIdentifier isEqualToString:productID]) {
                        self.latestSubscriptionProduct = product;
                        self.hasActiveSubscription = (self.latestSubscriptionExpirationDate && [currentDate beforeOrEqualTo:self.latestSubscriptionExpirationDate]);
                        break;
                    }
                }
            }
        }
    }

    NSInteger numOfSections = 0;
    if ([[IAPStoreHelper sharedInstance].storeProducts count]) {
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        numOfSections = 1;
        tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, self.tableView.bounds.size.width, 0.01f)];
    } else {
        UITextView *noProductsTextView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, tableView.bounds.size.height)];
        noProductsTextView.editable = NO;
        noProductsTextView.font =  [UIFont fontWithName:@"Helvetica" size:15.0f];
        noProductsTextView.textContainerInset = UIEdgeInsetsMake(60, 10, 0, 10);
        noProductsTextView.text = NSLocalizedStringWithDefaultValue(@"NO_PRODUCTS_TEXT", nil, [NSBundle mainBundle],
                                                                    @"Could not retrieve subscriptions from the App Store. Pull to refresh or try again later.",
                                                                    @"Subscriptions view text that is visible when the list of subscriptions is not available");
        noProductsTextView.textColor = [UIColor darkGrayColor];
        noProductsTextView.textAlignment    = NSTextAlignmentCenter;
        tableView.tableHeaderView = noProductsTextView;
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    }
    
    return numOfSections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(self.hasActiveSubscription) {
        return 1;
    }
    return [[IAPStoreHelper sharedInstance].storeProducts count];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView* cellView = [[UIView alloc] initWithFrame:CGRectZero];
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, cellView.bounds.size.width, cellView.bounds.size.height)];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textColor = [UIColor darkGrayColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [label.font fontWithSize:13];


    if(!self.hasActiveSubscription) {
        label.text = NSLocalizedStringWithDefaultValue(@"BUY_SUBSCRIPTIONS_HEADER_TEXT",
                                                       nil,
                                                       [NSBundle mainBundle],
                                                       @"Remove ads and surf the Internet faster with a premium subscription!",
                                                       @"Premium subscriptions dialog header text");

    } else {
        label.text = NSLocalizedStringWithDefaultValue(@"ACTIVE_SUBSCRIPTION_SECTION_TITLE",
                                                       nil,
                                                       [NSBundle mainBundle],
                                                       @"Current subscription",
                                                       @"Title of the section in the subscription dialog that shows currently active subscription information.");
   }
    [cellView addSubview:label];
    
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-5-[label]-5-|" options:0 metrics:nil views:@{ @"label": label}]];
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-10-[label]-10-|" options:0 metrics:nil views:@{ @"label": label}]];
    
    return cellView;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    UIView* cellView = [[UIView alloc] initWithFrame:CGRectZero];
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, cellView.bounds.size.width, cellView.bounds.size.height)];
    label.numberOfLines = 0;

    label.font = [label.font fontWithSize:13];
    label.textColor = [UIColor darkGrayColor];
    label.text = NSLocalizedStringWithDefaultValue(@"BUY_SUBSCRIPTIONS_NOTICES",
                                                   nil,
                                                   [NSBundle mainBundle],
                                                   @"A subscription is auto-renewable which means that once purchased it will be automatically renewed until you cancel it 24 hours prior to the end of the current period.\n\nYour iTunes Account will be charged for renewal within 24-hours prior to the end of the current period with the cost of subscription.",
                                                   @"Buy subscription dialog footer text");

    label.textAlignment = NSTextAlignmentLeft;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    [cellView addSubview:label];

    UIView *terms = [[UIView alloc] init];
    terms.translatesAutoresizingMaskIntoConstraints = NO;
    [cellView addSubview:terms];

    UIButton *privacyPolicyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [privacyPolicyButton addTarget:self action:@selector(openPrivacyPolicy) forControlEvents:UIControlEventTouchUpInside];

    [privacyPolicyButton setTitle:NSLocalizedStringWithDefaultValue(@"SUBSCRIPTIONS_PRIVACY_POLICY_BUTTON_TEXT",
                                                                    nil,
                                                                    [NSBundle mainBundle],
                                                                    @"Privacy Policy",
                                                                    @"Title of button on subscriptions page which opens Psiphon's privacy policy webpage")
                         forState:UIControlStateNormal];
    privacyPolicyButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    privacyPolicyButton.titleLabel.textColor = self.view.tintColor;
    privacyPolicyButton.titleLabel.font = [UIFont systemFontOfSize:12];
    privacyPolicyButton.titleLabel.numberOfLines = 0;

    privacyPolicyButton.translatesAutoresizingMaskIntoConstraints = NO;
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
    tosButton.titleLabel.textColor = self.view.tintColor;
    tosButton.titleLabel.font = [UIFont systemFontOfSize:12];
    tosButton.titleLabel.numberOfLines = 0;

    tosButton.translatesAutoresizingMaskIntoConstraints = NO;
    [terms addSubview:tosButton];


    // Manage subscriptions button
    UIButton *manageSubsButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [manageSubsButton setTitle:NSLocalizedStringWithDefaultValue(@"MANAGE_SUBSCRIPTIONS_BUTTON", nil, [NSBundle mainBundle], @"Manage my subscription", @"Manage subscription button")
                      forState:UIControlStateNormal];
    [manageSubsButton addTarget:self action:@selector(onManageSubscriptionTap) forControlEvents:UIControlEventTouchUpInside];
    manageSubsButton.translatesAutoresizingMaskIntoConstraints = FALSE;
    [cellView addSubview:manageSubsButton];

    NSString *restoreButtonTitle = NSLocalizedStringWithDefaultValue(@"RESTORE_SUBSCRIPTION_BUTTON_TITLE",
                                                                     nil,
                                                                     [NSBundle mainBundle],
                                                                     @"Restore my existing subscription",
                                                                     @"Restore my subscription button title");
    UIButton* restoreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [restoreButton setTitle:restoreButtonTitle forState:UIControlStateNormal];
    [restoreButton addTarget:self action:@selector(restoreAction) forControlEvents:UIControlEventTouchUpInside];
    restoreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cellView addSubview:restoreButton];
    
    NSString *refreshButtonTitle = NSLocalizedStringWithDefaultValue(@"REFRESH_APP_RECEIPT_BUTTON_TITLE",
                                                                     nil,
                                                                     [NSBundle mainBundle],
                                                                     @"Refresh app receipt",
                                                                     @"Refresh app receipt button title");
    UIButton* refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [refreshButton setTitle:refreshButtonTitle forState:UIControlStateNormal];
    [refreshButton addTarget:self action:@selector(refreshReceiptAction) forControlEvents:UIControlEventTouchUpInside];
    refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cellView addSubview:refreshButton];
    
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[terms]-|" options:0 metrics:nil views:@{ @"terms": terms}]];
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[label]-|" options:0 metrics:nil views:@{ @"label": label}]];
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[manageSubsButton]-|" options:0 metrics:nil views:@{ @"manageSubsButton": manageSubsButton}]];
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[restoreButton]-|" options:0 metrics:nil views:@{ @"restoreButton": restoreButton}]];
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[refreshButton]-|" options:0 metrics:nil views:@{ @"refreshButton": refreshButton}]];
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[terms(==30)]-[label]-10-[manageSubsButton]-10-[restoreButton]-10-[refreshButton]-|"
                                                                     options:0 metrics:nil
                                                                       views:@{ @"terms": terms, @"label": label, @"manageSubsButton": manageSubsButton, @"restoreButton": restoreButton, @"refreshButton": refreshButton}]];

    [privacyPolicyButton.heightAnchor constraintEqualToAnchor:terms.heightAnchor].active = YES;
    [privacyPolicyButton.centerYAnchor constraintEqualToAnchor:terms.centerYAnchor].active = YES;
    [privacyPolicyButton.leadingAnchor constraintEqualToAnchor:terms.leadingAnchor].active = YES;
    [privacyPolicyButton.trailingAnchor constraintEqualToAnchor:terms.centerXAnchor].active = YES;

    [tosButton.heightAnchor constraintEqualToAnchor:terms.heightAnchor].active = YES;
    [tosButton.centerYAnchor constraintEqualToAnchor:terms.centerYAnchor].active = YES;
    [tosButton.leadingAnchor constraintEqualToAnchor:terms.centerXAnchor].active = YES;
    [tosButton.trailingAnchor constraintEqualToAnchor:terms.trailingAnchor].active = YES;

    return cellView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IAPTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:iapCellID];
    if (cell == nil) {
        cell = [[IAPTableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:iapCellID];

        self.tableView.rowHeight = UITableViewAutomaticDimension;
        self.tableView.estimatedRowHeight = 66.0f;

        self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
        self.tableView.estimatedSectionFooterHeight = 66.0f;

        self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
        self.tableView.estimatedSectionHeaderHeight = 66.0f;
    }
    SKProduct * product = (SKProduct *) [IAPStoreHelper sharedInstance].storeProducts[indexPath.row];
    [self.priceFormatter setLocale:product.priceLocale];
    NSString *localizedPrice = [self.priceFormatter stringFromNumber:product.price];
    cell.textLabel.text = product.localizedTitle;
    cell.detailTextLabel.text = product.localizedDescription;

    if(self.hasActiveSubscription) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
        cell.accessoryView = nil;
        cell.textLabel.text = self.latestSubscriptionProduct.localizedTitle;
        cell.detailTextLabel.text = @"";
    } else {
        UISegmentedControl *buyButton = [[UISegmentedControl alloc]initWithItems:[NSArray arrayWithObject:localizedPrice]];
        self.buyButtonTintColor = buyButton.tintColor;
        buyButton.momentary = YES;
        buyButton.tag = indexPath.row;
        [buyButton addTarget:self
                      action:@selector(buyButtonPressed:)
            forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = buyButton;
    }

    return cell;
}

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

- (void)restoreAction {
    [self beginRefreshing];
    [[IAPStoreHelper sharedInstance] restoreSubscriptions];
}

- (void)refreshReceiptAction {
    [self beginRefreshing];
    [[IAPStoreHelper sharedInstance] refreshReceipt];
}

- (void)beginRefreshing {
    if (!self.refreshControl.isRefreshing) {
        [self.refreshControl beginRefreshing];
        [self.tableView setContentOffset:CGPointMake(0, self.tableView.contentOffset.y-self.refreshControl.frame.size.height) animated:YES];
    }
    // Timeout after 20 seconds
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self endRefreshing];
    });
}

- (void)endRefreshing {
    if (self.refreshControl.isRefreshing) {
        [self.refreshControl endRefreshing];
    }
}

- (void)dismissViewController {
    if (_openedFromSettings) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)reloadProducts {
    [self endRefreshing];
    [self.tableView reloadData];
}

- (void)startProductsRequest {
    [self beginRefreshing];
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
                    [buyButton setTintColor:self.buyButtonTintColor];
                } else {
                    [buyButton setTintColor:UIColor.grayColor];
                }
                
                buyButton.userInteractionEnabled = interactionEnabled;
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
