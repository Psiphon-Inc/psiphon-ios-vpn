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
#import "UIFont+Additions.h"
#import "Psiphon-Swift.h"

@interface IAPHelpViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic) UITableView *tableView;

@end

@implementation IAPHelpViewController {
    MBProgressHUD *buyProgressAlert;
    NSTimer *buyProgressAlertTimer;
    NSMutableArray <CAGradientLayer*> *buttonGradients;
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

    self.view.backgroundColor = UIColor.darkBlueColor;

    // Sets navigation bar title.
    self.title = NSLocalizedStringWithDefaultValue(@"RESTORE_SUBSCRIPTION_BUTTON", nil, [NSBundle mainBundle], @"Restore Subscription", @"Button which, when pressed, attempts to restore any existing subscriptions the user has purchased");

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onReceiptRefresh:)
                                                 name:IAPActorNotification.refreshReceipt
                                               object:nil];

}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    for (CAGradientLayer *buttonGradient in buttonGradients) {
        if (buttonGradient.superlayer) {
            buttonGradient.frame = buttonGradient.superlayer.bounds;
        }
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
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
    label.font = [UIFont avenirNextMedium:15.f];
    label.textColor = UIColor.whiteColor;
    label.text = helpDescription;
    label.textAlignment = NSTextAlignmentLeft;
    [cell.contentView addSubview:label];

    // Help button
    UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    button.backgroundColor = UIColor.lightishBlueTwo;
    button.layer.cornerRadius = 8;
    button.layer.masksToBounds = FALSE;
    button.titleEdgeInsets = UIEdgeInsetsMake(0.0, 24.0, 0.0, 24.0);
    [button setTitle:buttonTitle forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont avenirNextDemiBold:button.titleLabel.font.pointSize];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [cell.contentView addSubview:button];

    // Add background gradient to button
    CAGradientLayer *buttonGradient = [CAGradientLayer layer];
    buttonGradient.colors = @[(id)UIColor.lightRoyalBlueTwo.CGColor, (id)UIColor.lightishBlue.CGColor];
    buttonGradient.cornerRadius = button.layer.cornerRadius;
    [button.layer insertSublayer:buttonGradient atIndex:0];

    if (!buttonGradients) {
        buttonGradients = [[NSMutableArray alloc] init];
    }

    [buttonGradients addObject:buttonGradient];

    // Help label constraints
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor].active = TRUE;
    [label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor
                                    constant:16.f].active = TRUE;
    [label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor
                                        constant:16.f].active = TRUE;
    [label.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor
                                         constant:-16.f].active = TRUE;

    // Help button constraints
    button.translatesAutoresizingMaskIntoConstraints = FALSE;
    [button.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor].active = TRUE;
    [button.widthAnchor constraintEqualToConstant:250].active = TRUE;
    [button.heightAnchor constraintEqualToConstant:50].active = TRUE;
    [button.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:16.0].active = TRUE;

    [button.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor
                                        constant:-16.f].active = TRUE;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    UITableViewCell *cell = [[UITableViewCell alloc] init];

    if (indexPath.row == 0) {
        NSString *receiptButtonDescriptionHeader = NSLocalizedStringWithDefaultValue(@"REFRESH_APP_RECEIPT_BUTTON_DESCRIPTION_LIST_HEADER",
                                                                                     nil, [NSBundle mainBundle],
                                                                                     @"Refresh your app receipt when:",
                                                                                     @"Description text above a list of scenarios where the user should try refreshing their app receipt to restore an existing subscription");
        NSString *receiptButtonDescriptionPoint1 = NSLocalizedStringWithDefaultValue(@"REFRESH_APP_RECEIPT_BUTTON_DESCRIPTION_POINT_1",
                                                                                     nil, [NSBundle mainBundle],
                                                                                     @"You need to recover a subscription on your account with a new phone",
                                                                                     @"Point in a list of scenarios where the user should try refreshing their app receipt to restore an existing subscription");
        NSString *receiptButtonDescriptionPoint2 = NSLocalizedStringWithDefaultValue(@"REFRESH_APP_RECEIPT_BUTTON_DESCRIPTION_POINT_2",
                                                                                     nil, [NSBundle mainBundle],
                                                                                     @"You cannot see a subscription you purchased on this device",
                                                                                     @"Point in a list of scenarios where the user should try refreshing their app receipt to restore an existing subscription");
        [self createHelpCellContent:cell
                withHelpDescription:[NSString stringWithFormat:@"%@\n\n\u2022 %@\n\n\u2022 %@", receiptButtonDescriptionHeader, receiptButtonDescriptionPoint1, receiptButtonDescriptionPoint2]
                        buttonTitle:NSLocalizedStringWithDefaultValue(@"RESTORE_SUBSCRIPTION_BUTTON_TITLE",
                                                                      nil,
                                                                      [NSBundle mainBundle],
                                                                      @"Restore my subscription", @"Title of button which triggers an attempt to restore the user's existing subscription")
                             action:@selector(refreshReceiptAction)];
    }

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

- (void)refreshReceiptAction {
    [self showProgressSpinnerAndBlockUI];
    [SwiftAppDelegate.instance refreshReceipt];
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

- (void)reloadProducts {
    [self dismissProgressSpinnerAndUnblockUI];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)onReceiptRefresh:(NSNotification *)notification {
    [self dismissProgressSpinnerAndUnblockUI];

}

@end

