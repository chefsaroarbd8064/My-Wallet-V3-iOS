//
//  SideMenuViewController.m
//  Blockchain
//
//  Created by Mark Pfluger on 10/3/14.
//  Copyright (c) 2014 Blockchain Luxembourg S.A. All rights reserved.
//

#import "SideMenuViewController.h"
#import "RootService.h"
#import "ECSlidingViewController.h"
#import "BCCreateAccountView.h"
#import "BCEditAccountView.h"
#import "AccountTableCell.h"
#import "SideMenuViewCell.h"
#import "BCLine.h"
#import "PrivateKeyReader.h"
#import "UIViewController+AutoDismiss.h"
#import <JavaScriptCore/JavaScriptCore.h>

@interface SideMenuViewController ()

@property (strong, readwrite, nonatomic) UITableView *tableView;
@property (nonatomic) NSMutableArray *menuEntries;

@end

@implementation SideMenuViewController

ECSlidingViewController *sideMenu;

UITapGestureRecognizer *tapToCloseGestureRecognizerViewController;
UITapGestureRecognizer *tapToCloseGestureRecognizerTabBar;

NSString *entryKeyUpgradeBackup = @"upgrade_backup";
NSString *entryKeySettings = @"settings";
NSString *entryKeyAccountsAndAddresses = @"accounts_and_addresses";
NSString *entryKeyWebLogin = @"web_login";
NSString *entryKeyContacts = @"contacts";
NSString *entryKeyMerchantMap = @"merchant_map";
NSString *entryKeySupport = @"support";
NSString *entryKeyLogout = @"logout";
NSString *entryKeyBuyBitcoin = @"buy_bitcoin";

int balanceEntries = 0;
int accountEntries = 0;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    sideMenu = app.slidingViewController;
    
    self.tableView = ({
        UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width - sideMenu.anchorLeftPeekAmount, MENU_ENTRY_HEIGHT * self.menuEntriesCount) style:UITableViewStylePlain];
        tableView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleWidth;
        tableView.delegate = self;
        tableView.dataSource = self;
        tableView.opaque = NO;
        tableView.backgroundColor = [UIColor clearColor];
        tableView.backgroundView = nil;
        tableView.showsVerticalScrollIndicator = NO;
        tableView;
    });

    
    [self.view addSubview:self.tableView];
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    // Blue background for bounce area
    CGRect frame = self.view.bounds;
    frame.origin.y = -frame.size.height;
    UIView* blueView = [[UIView alloc] initWithFrame:frame];
    blueView.backgroundColor = COLOR_BLOCKCHAIN_BLUE;
    [self.tableView addSubview:blueView];
    // Make sure the refresh control is in front of the blue area
    blueView.layer.zPosition -= 1;
    
    sideMenu.delegate = self;
    
    tapToCloseGestureRecognizerViewController = [[UITapGestureRecognizer alloc] initWithTarget:app action:@selector(toggleSideMenu)];
    tapToCloseGestureRecognizerTabBar = [[UITapGestureRecognizer alloc] initWithTarget:app action:@selector(toggleSideMenu)];
}

- (NSUInteger)menuEntriesCount {
    return [self.menuEntries count];
}

- (NSDictionary *)getMenuEntry:(NSInteger)index {
    return [self.menuEntries objectAtIndex:index];
}

- (void)clearMenuEntries {
    self.menuEntries = [NSMutableArray new];
}

- (void)addMenuEntry:(NSString *)key text:(NSString *)text icon:(NSString *)icon {
    NSDictionary *entry = @{ @"key": key, @"text": text, @"icon": icon };
    [self.menuEntries addObject:entry];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self clearMenuEntries];
    
    if ([app.wallet isBuyEnabled]) {
        [self addMenuEntry:entryKeyBuyBitcoin text:BC_STRING_BUY_BITCOIN icon:@"bitcoin"];
    }
    if (!app.wallet.didUpgradeToHd) {
        [self addMenuEntry:entryKeyUpgradeBackup text:BC_STRING_UPGRADE icon:@"icon_upgrade"];
    } else {
        [self addMenuEntry:entryKeyUpgradeBackup text:BC_STRING_BACKUP_FUNDS icon:@"lock"];
    }

    [self addMenuEntry:entryKeySettings text:BC_STRING_SETTINGS icon:@"settings"];
#ifdef ENABLE_CONTACTS
    [self addMenuEntry:entryKeyContacts text:BC_STRING_CONTACTS icon:@"icon_contact_small"];
#endif
    [self addMenuEntry:entryKeyAccountsAndAddresses text:BC_STRING_ADDRESSES icon:@"wallet"];
    [self addMenuEntry:entryKeyWebLogin text:BC_STRING_LOG_IN_TO_WEB_WALLET icon:@"wallet"];
    [self addMenuEntry:entryKeyMerchantMap text:BC_STRING_MERCHANT_MAP icon:@"merchant"];
    [self addMenuEntry:entryKeySupport text:BC_STRING_SUPPORT icon:@"help"];
    [self addMenuEntry:entryKeyLogout text:BC_STRING_LOGOUT icon:@"logout"];

    [self setSideMenuGestures];
    [self reload];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self resetSideMenuGestures];
}

- (void)setSideMenuGestures
{
    TabViewcontroller *tabViewController = app.tabControllerManager.tabViewController;
    
    // Hide status bar
    if (!app.pinEntryViewController.inSettings) {
        [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:NO];
    }
    
    // Disable all interactions on main view
    for (UIView *view in tabViewController.activeViewController.view.subviews) {
        [view setUserInteractionEnabled:NO];
    }
    [tabViewController.menuSwipeRecognizerView setUserInteractionEnabled:NO];
    
    // Enable Pan gesture and tap gesture to close sideMenu
    [tabViewController.activeViewController.view setUserInteractionEnabled:YES];
    ECSlidingViewController *sideMenu = app.slidingViewController;
    [tabViewController.activeViewController.view addGestureRecognizer:sideMenu.panGesture];
    
    [tabViewController.activeViewController.view addGestureRecognizer:tapToCloseGestureRecognizerViewController];
    
    [tabViewController addTapGestureRecognizerToTabBar:tapToCloseGestureRecognizerTabBar];
    
    // Show shadow on current viewController in tabBarView
    UIView *castsShadowView = app.slidingViewController.topViewController.view;
    castsShadowView.layer.shadowOpacity = 0.3f;
    castsShadowView.layer.shadowRadius = 10.0f;
    castsShadowView.layer.shadowColor = [UIColor blackColor].CGColor;
}

- (void)resetSideMenuGestures
{
    TabViewcontroller *tabViewController = app.tabControllerManager.tabViewController;

    // Show status bar again
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:YES];
    
    // Disable Pan and Tap gesture on main view
    [tabViewController.activeViewController.view removeGestureRecognizer:sideMenu.panGesture];
    [tabViewController.activeViewController.view removeGestureRecognizer:tapToCloseGestureRecognizerViewController];
    [tabViewController removeTapGestureRecognizerFromTabBar:tapToCloseGestureRecognizerTabBar];

    // Enable interaction on main view
    for (UIView *view in tabViewController.activeViewController.view.subviews) {
        [view setUserInteractionEnabled:YES];
    }
    
    // Enable swipe to open side menu gesture on small bar on the left of main view
    [tabViewController.menuSwipeRecognizerView setUserInteractionEnabled:YES];
    [tabViewController.menuSwipeRecognizerView addGestureRecognizer:sideMenu.panGesture];
}

- (void)reload
{
    [self reloadNumberOfBalancesToDisplay];
    
    // Resize table view
    [self reloadTableViewSize];
    
    [self.tableView reloadData];
}

- (void)reloadTableView
{
    [self.tableView reloadData];
}

- (void)reloadNumberOfBalancesToDisplay
{
    // Total entries: 1 entry for the total balance, 1 for each HD account, 1 for the total legacy addresses balance (if needed)
    int numberOfAccounts = [app.wallet getActiveAccountsCount];
    balanceEntries = [[app.wallet activeLegacyAddresses] count] > 0 ? numberOfAccounts + 1 : numberOfAccounts;
    accountEntries = numberOfAccounts;
}

- (void)reloadTableViewSize
{
    self.tableView.frame = CGRectMake(0, 0, self.view.frame.size.width - sideMenu.anchorLeftPeekAmount, MENU_ENTRY_HEIGHT * self.menuEntriesCount + BALANCE_ENTRY_HEIGHT * (balanceEntries + 1) + SECTION_HEADER_HEIGHT + MENU_TOP_BANNER_HEIGHT);
    if (![self showBalances]) {
        self.tableView.frame = CGRectMake(0, 0, self.view.frame.size.width - sideMenu.anchorLeftPeekAmount, MENU_ENTRY_HEIGHT * self.menuEntriesCount + MENU_TOP_BANNER_HEIGHT);
    }
    
    // If the tableView is bigger than the screen, enable scrolling and resize table view to screen size
    if (self.tableView.frame.size.height > self.view.frame.size.height ) {
        self.tableView.frame = CGRectMake(0, 0, self.view.frame.size.width - sideMenu.anchorLeftPeekAmount, self.view.frame.size.height);
        
        // Add some extra space to bottom of tableview so things look nicer when scrolling all the way down
        self.tableView.contentInset = UIEdgeInsetsMake(0, 0, SECTION_HEADER_HEIGHT, 0);
        
        self.tableView.scrollEnabled = YES;
    }
    else {
        self.tableView.scrollEnabled = NO;
    }
}

- (Boolean)showBalances
{
    // Return true if the user has upgraded and either legacy adresses or multiple accounts
    return [app.wallet didUpgradeToHd] && ([[app.wallet activeLegacyAddresses] count] > 0 || [app.wallet getActiveAccountsCount] >= 2);
}

- (void)removeTransactionsFilter
{
    UITableViewHeaderFooterView *headerView = [self.tableView headerViewForSection:0];
    UIView *backgroundView = [[UIView alloc] initWithFrame:headerView.frame];
    [backgroundView setBackgroundColor:COLOR_BLOCKCHAIN_BLUE];
    headerView.backgroundView = backgroundView;
    
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:NO];
    
    [app removeTransactionsFilter];
}

#pragma mark - SlidingViewController Delegate

- (id<UIViewControllerAnimatedTransitioning>)slidingViewController:(ECSlidingViewController *)slidingViewController animationControllerForOperation:(ECSlidingViewControllerOperation)operation topViewController:(UIViewController *)topViewController
{
    // SideMenu will slide in
    if (operation == ECSlidingViewControllerOperationAnchorRight) {
        [self setSideMenuGestures];
    }
    // SideMenu will slide out
    else if (operation == ECSlidingViewControllerOperationResetFromRight) {
        // Everything happens in viewDidDisappear: which is called after the slide animation is done
    }
    
    return nil;
}

#pragma mark - UITableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self showBalances]) {
        if (indexPath.section != 1) {
#ifdef ENABLE_TRANSACTION_FILTERING
            BOOL deselected = NO;
            
            if (indexPath.row == [self tableView:tableView numberOfRowsInSection:indexPath.section] - 1 && [[app.wallet activeLegacyAddresses] count] > 0) {
                if ([app filterIndex] == FILTER_INDEX_IMPORTED_ADDRESSES) {
                    deselected = YES;
                } else {
                }
            } else {
                if ([app.wallet getIndexOfActiveAccount:(int)indexPath.row] == [app filterIndex]) {
                    deselected = YES;
                } else {
                    
                }
            }
            
            if (deselected) {
                [self removeTransactionsFilter];
                [tableView deselectRowAtIndexPath:indexPath animated:NO];
            } else {
                UITableViewHeaderFooterView *headerView = [tableView headerViewForSection:indexPath.section];
                UIView *backgroundView = [[UIView alloc] initWithFrame:headerView.frame];
                [backgroundView setBackgroundColor:COLOR_BLOCKCHAIN_BLUE];
                headerView.backgroundView = backgroundView;
            }
#endif
            return;
        }
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *rowKey = [self getMenuEntry:indexPath.row][@"key"];

    if (rowKey == entryKeyUpgradeBackup) {
        BOOL didUpgradeToHD = app.wallet.didUpgradeToHd;
        if (didUpgradeToHD) {
            [app backupFundsClicked:nil];
        } else {
            [app showHdUpgrade];
        }
    } else if (rowKey == entryKeyAccountsAndAddresses) {
        [app accountsAndAddressesClicked:nil];
    } else if (rowKey == entryKeySettings) {
        [app accountSettingsClicked:nil];
    } else if (rowKey == entryKeyContacts) {
        [app contactsClicked:nil];
    } else if (rowKey == entryKeyWebLogin) {
        [app webLoginClicked:nil];
    } else if (rowKey == entryKeyMerchantMap) {
        [app merchantClicked:nil];
    } else if (rowKey == entryKeySupport) {
        [app supportClicked:nil];
    } else if (rowKey == entryKeyLogout) {
        [app logoutClicked:nil];
    } else if (rowKey == entryKeyBuyBitcoin) {
        [app buyBitcoinClicked:nil];
    }
}

#pragma mark - UITableView Datasource

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (![self showBalances]) {
        return MENU_ENTRY_HEIGHT;
    }
    if (indexPath.section != 2) {
        return BALANCE_ENTRY_HEIGHT;
    }
    return MENU_ENTRY_HEIGHT;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Empty table if not logged in:
    if (!app.wallet.guid) {
        return 0;
    }
    
    return 2;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section == 0) {
        return MENU_TOP_BANNER_HEIGHT;
    }
    
    return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    // Total Balance
    if (section == 0) {
        UITableViewHeaderFooterView *view = [[UITableViewHeaderFooterView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width, MENU_TOP_BANNER_HEIGHT)];
        UIView *backgroundView = [[UIView alloc] initWithFrame:view.frame];

        [backgroundView setBackgroundColor:COLOR_BLOCKCHAIN_BLUE];
        view.backgroundView = backgroundView;
        
        return view;
    }
    
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)sectionIndex
{
    if (sectionIndex == 0) {
        return 0;
    }
    if (sectionIndex == 1) {
        return self.menuEntriesCount;
    }
    
    return balanceEntries;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellIdentifier;
    
    if (indexPath.section == 1) {

        cellIdentifier = @"CellMenu";
        
        SideMenuViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        
        if (cell == nil) {
            cell = [[SideMenuViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
            
            UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cell.frame.size.width, cell.frame.size.height)];
            [v setBackgroundColor:COLOR_TABLE_VIEW_CELL_SELECTED_LIGHT_GRAY];
            cell.selectedBackgroundView = v;
        }

        NSDictionary *entry = [self getMenuEntry:indexPath.row];
        cell.textLabel.text = entry[@"text"];
        cell.textLabel.adjustsFontSizeToFitWidth = YES;
        NSString *imageName = entry[@"icon"];
        cell.imageView.image = [UIImage imageNamed:imageName];
        
        if ([imageName isEqualToString:@"icon_contact_small"]) {
            cell.imageView.image = [cell.imageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [cell.imageView setTintColor:COLOR_DARK_GRAY];
        }
        
        return cell;
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([cell respondsToSelector:@selector(setSeparatorInset:)]) {
        if ([self showBalances]) {
            // Custom separator inset
            float leftInset = (indexPath.section != 1) ? 56 : 15;
            [cell setSeparatorInset:UIEdgeInsetsMake(0, leftInset, 0, 0)];
            
            // No separator for non-account side menu items
            if ((indexPath.section == 0 && indexPath.row == balanceEntries - 1) || indexPath.section == 1) {
                [cell setSeparatorInset:UIEdgeInsetsMake(0, 15, 0, CGRectGetWidth(cell.bounds)-15)];
            }
        } else {
            // No separator
            [cell setSeparatorInset:UIEdgeInsetsMake(0, 15, 0, CGRectGetWidth(cell.bounds)-15)];
        }
    }
}

@end
