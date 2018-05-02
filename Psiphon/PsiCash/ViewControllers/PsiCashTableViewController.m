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

#import "PsiCashTableViewController.h"
#import "PsiCashBalanceView.h"
#import "PsiCashBalanceTableViewCell.h"
#import "PsiCashClient.h"
#import "PsiCashClientModel.h"
#import "PsiCashPurchaseAlertView.h"
#import "PsiCashSpeedBoostTableViewCell.h"
#import "ReactiveObjC.h"

#define kNumSections 3

@interface PsiCashTableViewController ()
@property (atomic, readwrite) PsiCashClientModel *model;
@end

@implementation PsiCashTableViewController {
    RACDisposable *clientModelUpdates;
    PsiCashPurchaseAlertView *alertView;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    if (!_openedFromSettings) {
        NSString* rightButtonTitle = NSLocalizedStringWithDefaultValue(@"DONE_ACTION", nil, [NSBundle mainBundle], @"Done", @"Title of the button that dismisses the subscriptions menu");
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                                                  initWithTitle:rightButtonTitle
                                                  style:UIBarButtonItemStyleDone
                                                  target:self
                                                  action:@selector(dismissViewController)];
    }

    self.tableView.backgroundColor = [UIColor colorWithRed:0.98 green:0.98 blue:0.97 alpha:1.0];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    __weak PsiCashTableViewController *weakSelf = self;
    clientModelUpdates = [[PsiCashClient.sharedInstance.clientModelSignal deliverOnMainThread] subscribeNext:^(PsiCashClientModel *newClientModel) {
        __strong PsiCashTableViewController *strongSelf = weakSelf;
        if (strongSelf != nil) {
            BOOL stateChanged = [self.model hasActiveSpeedBoostPurchase] ^ [newClientModel hasActiveSpeedBoostPurchase] || [self.model hasPendingPurchase] ^ [newClientModel hasPendingPurchase];

            self.model = newClientModel;

            if (stateChanged && alertView != nil) {
                [self showPurchaseAlertView];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
            });
        }
    }];
}

- (void)dealloc {
    [clientModelUpdates dispose];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kNumSections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < kNumSections - 1) {
        return 1;
    } else if (section == kNumSections - 1) {
        return 2;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            PsiCashBalanceTableViewCell *balanceCell = [[PsiCashBalanceTableViewCell alloc] init];
            [balanceCell bindWithModel:self.model];
            cell = balanceCell;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            PsiCashSpeedBoostTableViewCell *speedBoostMeterCell = [[PsiCashSpeedBoostTableViewCell alloc] init];
            [speedBoostMeterCell bindWithModel:self.model];
            cell = speedBoostMeterCell;
        }
    } else if (indexPath.section == 2) {
        cell = [[UITableViewCell alloc] init];
    }

    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kNumSections - 1) {
        return 60;
    }
    return 120;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (section < kNumSections) {
        UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 18)];
        UILabel *label = [[UILabel alloc] init];
        label.font = [UIFont boldSystemFontOfSize:12];

        if (section == 0) {
            label.text = @"Balance";
        } else if (section == 1) {
            label.text = @"Speed Boost";
        } else if (section == 2) {
            label.text = @"Info";
        }

        [view addSubview:label];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [label.centerXAnchor constraintEqualToAnchor:view.centerXAnchor].active = YES;
        [label.centerYAnchor constraintEqualToAnchor:view.centerYAnchor].active = YES;

        return view;
    }
    return NULL;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section < kNumSections - 1) {
        return 20;
    } else if (section == kNumSections - 1) {
        return 40;
    }
    return 0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        [self showPurchaseAlertView];
    }
}

#pragma mark - PsiCashPurchaseAlertViewDelegate protocol

- (void)stateBecameStale {
    [alertView close];
    alertView = nil;
}

- (void)showPurchaseAlertView {
    if (alertView != nil) {
        [alertView close];
        alertView = nil;
    }

    if ([self.model hasActiveSpeedBoostPurchase]) {
        alertView = [PsiCashPurchaseAlertView alreadySpeedBoostingAlertWithNMinutesRemaining:[self.model minutesOfSpeedBoostRemaining]];
    } else  if ([self.model hasPendingPurchase]) {
        alertView = [PsiCashPurchaseAlertView pendingPurchaseAlert];
    } else {
        alertView = [PsiCashPurchaseAlertView purchaseAlert];
    }

    alertView.controllerDelegate = self;
    [alertView bindWithModel:self.model];
    [alertView show];
}

#pragma mark - Navigation

- (void)dismissViewController {
    if (_openedFromSettings) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end

