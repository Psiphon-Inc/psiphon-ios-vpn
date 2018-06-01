/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import "IAPHelpViewController.h"
#import "Logging.h"

@interface IAPHelpViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic) UITableView *tableView;

@end

@implementation IAPHelpViewController {
    MBProgressHUD *buyProgressAlert;
    NSTimer *buyProgressAlertTimer;
}

- (void)loadView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 152.0;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 0, 0, 0);
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.view = self.tableView;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Sets screen background and navigation bar colours.
    self.view.backgroundColor = UIColor.charcoalGreyColor;
    self.navigationController.navigationBar.barTintColor = UIColor.charcoalGreyColor;  // Navigation bar background color
    self.navigationController.navigationBar.tintColor = UIColor.purpleButtonColor;  // Navigation bar items color
    [self.navigationController.navigationBar setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor}];

    // Sets navigation bar title.
    // TODO: localize
    self.title = @"Restore Subscription";

    // Listens to IAPStoreHelper transaction states.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPaymentTransactionUpdate:)
                                                 name:IAPHelperPaymentTransactionUpdateNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPaymentTransactionUpdate:)
                                                 name:IAPSKProductsRequestDidFailWithErrorNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPaymentTransactionUpdate:)
                                                 name:IAPSKProductsRequestDidReceiveResponseNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPaymentTransactionUpdate:)
                                                 name:IAPSKRequestRequestDidFinishNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPaymentTransactionUpdate:)
                                                 name:IAPHelperUpdatedSubscriptionDictionaryNotification
                                               object:nil];

}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 2;
}

#pragma mark - TableView Cells

- (void)createHelpCellContent:(UITableViewCell *)cell
          withHelpDescription:(NSString *)helpDescription
                  buttonTitle:(NSString *)buttonTitle
                       action:(SEL)action {

    cell.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    // Help label
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    label.font = [label.font fontWithSize:15];
    label.textColor = UIColor.whiteColor;
    label.text = helpDescription;
    label.textAlignment = NSTextAlignmentLeft;
    [cell.contentView addSubview:label];

    // Help button
    UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    button.backgroundColor = UIColor.purpleButtonColor;
    button.layer.cornerRadius = 5.0;
    button.layer.masksToBounds = FALSE;
    button.titleEdgeInsets = UIEdgeInsetsMake(0.0, 24.0, 0.0, 24.0);
    [button setTitle:buttonTitle forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [cell.contentView addSubview:button];

    // Help label constraints
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor].active = TRUE;
    [label autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:16.0].active = TRUE;
    [label autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:16.0].active = TRUE;
    [label autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:16.0].active = TRUE;

    // Help button constraints
    button.translatesAutoresizingMaskIntoConstraints = FALSE;
    [button.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor].active = TRUE;
    [button.widthAnchor constraintEqualToConstant:250].active = TRUE;
    [button.heightAnchor constraintEqualToConstant:50].active = TRUE;
    [button.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:16.0].active = TRUE;
    [button autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:16.0].active = TRUE;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    UITableViewCell *cell = [[UITableViewCell alloc] init];

    // TODO: localize
    if (indexPath.row == 0) {
        [self createHelpCellContent:cell
                withHelpDescription:@"If you can’t see your subscription, there may be an issue with something something. Start by etc etc the more common problem."
                        buttonTitle:@"Refresh app receipt"
                             action:@selector(refreshReceiptAction)];
    }

    if (indexPath.row == 1) {
        [self createHelpCellContent:cell
                withHelpDescription:@"If you’re trying to recover a subscription on your account with a new phone, try this."
                        buttonTitle:@"Restore existing subscription"
                             action:@selector(refreshReceiptAction)];
    }

    return cell;
}

#pragma mark - Footer

- (nullable UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    UIView *cell = [[UIView alloc] initWithFrame:CGRectZero];

    cell.backgroundColor = UIColor.clearColor;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    label.font = [label.font fontWithSize:15];
    label.textColor = UIColor.whiteColor;
    // TODO: localize
    label.text = @"Still experiencing issues? Contact support";
    label.textAlignment = NSTextAlignmentCenter;
    [cell addSubview:label];

    label.translatesAutoresizingMaskIntoConstraints = FALSE;
    [label.heightAnchor constraintEqualToAnchor:cell.heightAnchor].active = YES;
    [label.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor].active = YES;
    [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor].active = YES;
    [label.topAnchor constraintEqualToAnchor:cell.topAnchor constant:16.0].active = TRUE;

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

- (void)restoreAction {
    [[IAPStoreHelper sharedInstance] restoreSubscriptions];
}

- (void)refreshReceiptAction {
    [[IAPStoreHelper sharedInstance] refreshReceipt];
}

- (void)dismissViewController {
    [self.navigationController popViewControllerAnimated:YES];
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

- (void)onPaymentTransactionUpdate:(NSNotification *)notification {
    SKPaymentTransactionState transactionState = (SKPaymentTransactionState) [notification.userInfo[IAPHelperPaymentTransactionUpdateKey] integerValue];

    LOG_DEBUG(@"test transaction state %d", transactionState);
    
    if (SKPaymentTransactionStatePurchasing == transactionState) {
        [self showProgressSpinnerAndBlockUI];
    } else {
        [self dismissProgressSpinnerAndUnblockUI];
    }
}

@end

