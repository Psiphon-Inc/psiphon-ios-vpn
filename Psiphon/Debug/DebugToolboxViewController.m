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

#import <SafariServices/SafariServices.h>
#import "DebugToolboxViewController.h"
#import "Asserts.h"
#import "Notifier.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "DebugDirectoryViewerViewController.h"
#import "PersistentContainerWrapper.h"
#import "Logging.h"
#import "Psiphon-Swift.h"
#import "UIAlertController+Additions.h"
#import "AppFiles.h"

#if DEBUG || DEV_RELEASE

NSString * const UserDefaultsPsiCashUsername = @"Testing-Account-Username";
NSString * const UserDefaultsPsiCashPassword = @"Testing-Account-Password";

NSString * const ActionCellIdentifier = @"ActionCell";
NSString * const SwitchCellIdentifier = @"SwitchCell";
NSString * const StateCellIdentifier = @"StateCell";

@interface DebugToolboxViewController () <NotifierObserver>

@property (nonatomic) PsiphonDataSharedDB *sharedDB;

@end

@implementation DebugToolboxViewController {
    UITableView *actionsTableView;
    UILabel *psiphonTunnelConnectionStateLabel;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:PsiphonAppGroupIdentifier];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Navigation bar
    self.title = @"Toolbox";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                 target:self
                                 action:@selector(dismiss)];

    actionsTableView = [[UITableView alloc] init];
    actionsTableView.dataSource = self;
    actionsTableView.delegate = self;
    [actionsTableView registerClass:UITableViewCell.class forCellReuseIdentifier:ActionCellIdentifier];
    [actionsTableView registerClass:UITableViewCell.class forCellReuseIdentifier:SwitchCellIdentifier];
    [actionsTableView registerClass:UITableViewCell.class forCellReuseIdentifier:StateCellIdentifier];
    if (@available(iOS 13.0, *)) {
        actionsTableView.backgroundColor = UIColor.systemBackgroundColor;
    } else {
        // Fallback on earlier versions
        actionsTableView.backgroundColor = [UIColor whiteColor];
    }
    [self.view addSubview:actionsTableView];

    // Layout constraints
    actionsTableView.translatesAutoresizingMaskIntoConstraints = FALSE;
    [actionsTableView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = TRUE;
    [actionsTableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = TRUE;
    [actionsTableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = TRUE;
    [actionsTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = TRUE;

    // Register to Notifier messages.
    [[Notifier sharedInstance] registerObserver:self callbackQueue:dispatch_get_main_queue()];
}

- (void)dismiss {
    [self dismissViewControllerAnimated:TRUE completion:nil];
}

#pragma mark - UITableViewDataSource delegate methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2; // PPROF
        case 1: return 3; // EXTENSION
        case 2: return 1; // PSIPHON TUNNEL
        case 3: return 5; // CONTAINER
        default:
            PSIAssert(FALSE)
            return 0;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"PPROF";
        case 1: return @"EXTENSION";
        case 2: return @"PSIPHON TUNNEL";
        case 3: return @"CONTAINER";
        default:
            PSIAssert(FALSE);
            return @"";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell;
    SEL action = nil;

    // PPROF section
    if (indexPath.section == 0) {

        cell = [tableView dequeueReusableCellWithIdentifier:ActionCellIdentifier forIndexPath:indexPath];
        switch (indexPath.row) {
            case 0: {
                cell.textLabel.text = @"Write Go Profiles";
                action = @selector(onWriteGoProfiles);
                break;
            }
            case 1: {
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.textLabel.text = @"Show Go Profiles";
                action = @selector(onGoProfiles);
                break;
            }
        }

    // EXTENSION section
    } else if (indexPath.section == 1) {
        cell = [tableView dequeueReusableCellWithIdentifier:ActionCellIdentifier
          forIndexPath:indexPath];

        switch (indexPath.row) {
            case 0: {
                cell.textLabel.text = @"Custom Function";
                action = @selector(onCustomFunction);
                break;
            }
            case 1: {
                cell.textLabel.text = @"Force Jetsam";
                action = @selector(onForceJetsam);
                break;
            }
            case 2: {
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.textLabel.text = @"Memory Profiler";
                UISwitch *switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
                [switchView setOn:self.sharedDB.getDebugMemoryProfiler];
                [switchView addTarget:self
                               action:@selector(onMemoryProfilerSwitch:)
                     forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = switchView;
                break;
            }
        }

    // PSIPHON TUNNEL section
    } else if (indexPath.section == 2) {

        cell = [tableView dequeueReusableCellWithIdentifier:ActionCellIdentifier
                                               forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        switch (indexPath.row) {
            case 0: {
                psiphonTunnelConnectionStateLabel = [[UILabel alloc] init];
                psiphonTunnelConnectionStateLabel.textColor = UIColor.brownColor;
                cell.textLabel.text = @"Connection State";
                cell.accessoryView = psiphonTunnelConnectionStateLabel;
                [self updateConnectionStateLabel];
                break;
            }
        }

    // CONTAINER section
    } else if (indexPath.section == 3) {
        cell = [tableView dequeueReusableCellWithIdentifier:ActionCellIdentifier
                                               forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        switch (indexPath.row) {
            case 0: {
                cell.textLabel.text = @"Default PsiCash Accounts credentials";
                action = @selector(onDefaultAccountsCredentials);
                break;
            }
            case 1: {
                cell.textLabel.text = @"Reset Standard UserDefaults";
                action = @selector(onResetStandardUserDefaults);
                break;
            }
            case 2: {
                cell.textLabel.text = @"Reset PsiphonDataSharedDB";
                action = @selector(onResetPsiphonDataSharedDB);
                break;
            }
            case 3: {
                cell.textLabel.text = @"Delete Core Data persistent store";
                action = @selector(onDeleteCoreDataPersistentStores);
                break;
            }
            case 4: {
                cell.textLabel.text = @"Delete PsiCash store directory";
                action = @selector(onDeletePsiCashStore);
                break;
            }
        }
    }

    if (action != nil) {
        UITapGestureRecognizer *gr = [[UITapGestureRecognizer alloc]
                initWithTarget:self action:action];
        [cell addGestureRecognizer:gr];
    }

    return cell;
}

#pragma mark - Action cell tap delegates

- (void)onCustomFunction {
    [[Notifier sharedInstance] post:NotifierDebugCustomFunction];
}

- (void)onForceJetsam {
    [[Notifier sharedInstance] post:NotifierDebugForceJetsam];
}

- (void)onWriteGoProfiles {
    [[Notifier sharedInstance] post:NotifierDebugGoProfile];
}

- (void)onGoProfiles {
    DebugDirectoryViewerViewController *wvc = [DebugDirectoryViewerViewController
            createAndLoadDirectory:self.sharedDB.goProfileDirectory
            withTitle:@"Go Profiles"];
    [self.navigationController pushViewController:wvc animated:TRUE];
}

- (void)onMemoryProfilerSwitch:(UISwitch *)view {
    [self.sharedDB setDebugMemoryProfiler:view.isOn];
    [[Notifier sharedInstance] post:NotifierDebugMemoryProfiler];
}

- (void)onDefaultAccountsCredentials {
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"PsiCash Account" message:@"Set your default credentials" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Username";
        textField.text =[[NSUserDefaults standardUserDefaults] valueForKey:UserDefaultsPsiCashUsername];
        textField.clearButtonMode = UITextFieldViewModeAlways;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Password";
        textField.text =[[NSUserDefaults standardUserDefaults] valueForKey:UserDefaultsPsiCashPassword];
        textField.clearButtonMode = UITextFieldViewModeAlways;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [[NSUserDefaults standardUserDefaults] setValue:alert.textFields[0].text
                                                 forKey:UserDefaultsPsiCashUsername];
        [[NSUserDefaults standardUserDefaults] setValue:alert.textFields[1].text
                                                 forKey:UserDefaultsPsiCashPassword];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)onResetStandardUserDefaults {
    [self clearUserDefaults:[NSUserDefaults standardUserDefaults]];
    [self presentAlertWithTitle:@"NSUserDefaults" andMessage:@"Cleared standardUserDefaults"];
}

- (void)onResetPsiphonDataSharedDB {
    NSUserDefaults *sharedDB = [[NSUserDefaults alloc] initWithSuiteName:PsiphonAppGroupIdentifier];
    [self clearUserDefaults:sharedDB];
    [self presentAlertWithTitle:@"NSUserDefaults" andMessage:@"Cleared PsiphonDataSharedDB"];
}

- (void)onDeleteCoreDataPersistentStores {
    
    // Deletes SharedModel persistent store.
    NSError *error = nil;
    [[SwiftDelegate.bridge sharedCoreData] destroyPersistentStoreAndReturnError:&error];
    
    if (error != nil) {
        LOG_DEBUG(@"Failed to delete SharedModel persistent store: %@", error);
        [self presentAlertWithTitle:@"Error" andMessage:@"Failed to delete persistent store"];
    } else {
        [self presentAlertWithTitle:@"Success" andMessage:@"Deleted persistent store"];
    }
    
    LOG_DEBUG(@"SharedModel sql URL: %@", [AppFiles sharedSqliteDB]);
    
}

- (void)onDeletePsiCashStore {
    
    NSString *_Nullable dirPath = [SwiftDelegate.bridge getPsiCashStoreDir];
    
    if (dirPath == nil) {
        [self presentAlertWithTitle:@"Error" andMessage:@"PsiCash store dir not defined"];
        return;
    }
    
    NSError *error = nil;
    [NSFileManager.defaultManager removeItemAtPath:dirPath error:&error];
    
    if (error != nil) {
        LOG_DEBUG(@"Failed to delete PsiCash store dir: %@", error.description);
        [self presentAlertWithTitle:@"Error" andMessage:@"Failed to delete PsiCash store dir"];
    } else {
        [self presentAlertWithTitle:@"Success" andMessage:@"Deleted PsiCash store dir"];
    }
    
}

- (void)presentAlertWithTitle:(NSString *)title andMessage:(NSString *)message {
    [UIAlertController presentSimpleAlertWithTitle:title
                                           message:message
                                    preferredStyle:UIAlertControllerStyleAlert
                                         okHandler:nil];
}

#pragma mark - Connection state

- (void)updateConnectionStateLabel {
    psiphonTunnelConnectionStateLabel.text = [self.sharedDB getDebugPsiphonConnectionState];
    [psiphonTunnelConnectionStateLabel sizeToFit];
}

- (void)onMessageReceived:(NotifierMessage)message {

    if ([NotifierDebugPsiphonTunnelState isEqualToString:message]) {
        [self updateConnectionStateLabel];
    }

}

#pragma mark - Helper methods

- (void)clearUserDefaults:(NSUserDefaults *)userDefaults {
    NSDictionary<NSString *, id> *dictRepr = [userDefaults dictionaryRepresentation];
    for (NSString *key in dictRepr) {
        [userDefaults removeObjectForKey:key];
    }
}

@end

#endif
