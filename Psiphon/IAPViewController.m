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
#import "IAPStoreHelper.h"
#import "IAPReceiptHelper.h"


static NSString *iapCellID = @"IAPTableCellID";

@interface IAPTableViewCell : UITableViewCell
@end


@interface IAPViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSNumberFormatter *priceFormatter;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@end


@implementation IAPViewController {
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
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if([[IAPStoreHelper sharedInstance].storeProducts count] == 0) {
        // retry getting products from the store
        [self startProductsRequest];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProducts)
                                                 name:kIAPSKProductsRequestDidFailWithError
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProducts)
                                                 name:kIAPSKProductsRequestDidReceiveResponse
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProducts)
                                                 name:kIAPSKPaymentTransactionStatePurchased
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProducts)
                                                 name:kIAPSKPaymentQueuePaymentQueueRestoreCompletedTransactionsFinished
                                               object:nil];    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProducts)
                                                 name:kIAPSKPaymentQueueRestoreCompletedTransactionsFailedWithError
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProducts)
                                                 name:kIAPSKRequestRequestDidFinish
                                               object:nil];

}


- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}



#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger numOfSections = 0;
    if ([[IAPStoreHelper sharedInstance].storeProducts count]) {
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        numOfSections                 = 1;
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
    return [[IAPStoreHelper sharedInstance].storeProducts count];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView* cellView = [[UIView alloc] initWithFrame:CGRectZero];
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, cellView.bounds.size.width, cellView.bounds.size.height)];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.font = [label.font fontWithSize:13];
    label.textColor = [UIColor darkGrayColor];
    label.text = NSLocalizedStringWithDefaultValue(@"BUY_SUBSCRIPTIONS_HEADER_TEXT",
                                                   nil,
                                                   [NSBundle mainBundle],
                                                   @"Remove ads and surf the Internet faster with a premium subscription!",
                                                   @"Premium subscriptions dialog header text");
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    
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
    label.text = NSLocalizedStringWithDefaultValue(@"BUY_SUBSCRIPTIONS_FOOTER_TEXT",
                                                   nil,
                                                   [NSBundle mainBundle],
                                                   @"A subscription is auto-renewable which means that once purchased it will be automatically renewed until you cancel it 24 hours prior to the end of the current period.\n\nYour iTunes Account will be charged for renewal within 24-hours prior to the end of the current period with the cost of subscription.\n\nManage your Subscription and Auto-Renewal by going to your Account Settings.",
                                                   @"Buy subscription dialog footer text");
    label.textAlignment = NSTextAlignmentLeft;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    
    [cellView addSubview:label];
    
    
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
    

    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[label]-|" options:0 metrics:nil views:@{ @"label": label}]];
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[restoreButton]-|" options:0 metrics:nil views:@{ @"restoreButton": restoreButton}]];
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[refreshButton]-|" options:0 metrics:nil views:@{ @"refreshButton": refreshButton}]];
    [cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-10-[label]-10-[restoreButton]-10-[refreshButton]-|"
                                                                     options:0 metrics:nil
																	   views:@{ @"label": label, @"restoreButton": restoreButton, @"refreshButton": refreshButton}]];
    
    return cellView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SKProduct * product = (SKProduct *) [IAPStoreHelper sharedInstance].storeProducts[indexPath.row];
    
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
    
    [self.priceFormatter setLocale:product.priceLocale];
    NSString *localizedPrice = [self.priceFormatter stringFromNumber:product.price];
    cell.detailTextLabel.text = product.localizedDescription;
    cell.textLabel.text = product.localizedTitle;
    
    RMAppReceipt *receipt = [[IAPReceiptHelper sharedInstance] appReceipt];
    BOOL isActiveSubscription = NO;
    NSDate *subscriptionExpirationDate = nil;

	if(receipt) {
        subscriptionExpirationDate = [receipt expirationDateForProduct:product.productIdentifier];
        isActiveSubscription = (subscriptionExpirationDate && [[NSDate date] compare:subscriptionExpirationDate] != NSOrderedDescending);
	}

    if (isActiveSubscription) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
        cell.accessoryView = nil;

		NSString *detailTextFormat = NSLocalizedStringWithDefaultValue(@"ACTIVE_SUBSCRIPTION_DETAIL_TEXT",
																					 nil,
																					 [NSBundle mainBundle],
																					 @"Expires on %@, renewal cost is %@",
																 @"Active subscription detail text, example: Expires on 2017-01-01, renewal cost is $3.99");

		NSDateFormatter* df = [NSDateFormatter new];
		df.dateFormat= [NSDateFormatter dateFormatFromTemplate:@"MMddYY" options:0 locale:[NSLocale currentLocale]];
		NSString *dateString = [df stringFromDate:subscriptionExpirationDate];

		cell.detailTextLabel.text = [NSString stringWithFormat:detailTextFormat, dateString, localizedPrice];
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

- (void)restoreAction {
    if (!self.refreshControl.isRefreshing) {
        [self.refreshControl beginRefreshing];
        [self.tableView setContentOffset:CGPointMake(0, self.tableView.contentOffset.y-self.refreshControl.frame.size.height) animated:YES];
    }
    [[IAPStoreHelper sharedInstance] restoreSubscriptions];
}

- (void)refreshReceiptAction {
    if (!self.refreshControl.isRefreshing) {
        [self.refreshControl beginRefreshing];
        [self.tableView setContentOffset:CGPointMake(0, self.tableView.contentOffset.y-self.refreshControl.frame.size.height) animated:YES];
    }
    [[IAPStoreHelper sharedInstance] refreshReceipt];
}

- (void)dismissViewController {
    if (_openedFromSettings) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)reloadProducts {
    if (self.refreshControl.isRefreshing) {
        [self.refreshControl endRefreshing];
    }
    [self.tableView reloadData];
}

- (void) startProductsRequest {
    if (!self.refreshControl.isRefreshing) {
        [self.refreshControl beginRefreshing];
        [self.tableView setContentOffset:CGPointMake(0, self.tableView.contentOffset.y-self.refreshControl.frame.size.height) animated:YES];
    }
    [[IAPStoreHelper sharedInstance] startProductsRequest];
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

