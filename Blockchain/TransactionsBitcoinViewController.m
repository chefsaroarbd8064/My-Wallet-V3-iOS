//
//  TransactionsViewController.m
//  Blockchain
//
//  Created by Ben Reeves on 10/01/2012.
//  Copyright (c) 2012 Blockchain Luxembourg S.A. All rights reserved.
//

#import "TransactionsBitcoinViewController.h"
#import "Transaction.h"
#import "TransactionTableCell.h"
#import "MultiAddressResponse.h"
#import "RootService.h"
#import "TransactionDetailViewController.h"
#import "Contact.h"
#import "ContactTransaction.h"
#import "ContactTransactionTableViewCell.h"
#import "BCAddressSelectionView.h"
#import "TransactionDetailNavigationController.h"

@interface TransactionsBitcoinViewController () <AddressSelectionDelegate, UIScrollViewDelegate, ContactTransactionCellDelegate>

@property (nonatomic) int sectionMain;
@property (nonatomic) int sectionContactsPending;

@property (nonatomic) UIView *bounceView;

@property (nonatomic) UILabel *noTransactionsTitle;
@property (nonatomic) UILabel *noTransactionsDescription;
@property (nonatomic) UIButton *getBitcoinButton;

@property (nonatomic) UIView *noTransactionsView;

@property (nonatomic) NSArray *finishedTransactions;

@end

@implementation TransactionsBitcoinViewController

@synthesize data;
@synthesize latestBlock;

BOOL didReceiveTransactionMessage;
BOOL hasZeroTotalBalance = NO;

UIRefreshControl *refreshControl;
int lastNumberTransactions = INT_MAX;

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    [self updateData:app.latestResponse];
    
    [self reload];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return app.wallet.pendingContactTransactions.count > 0 ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)_tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == self.sectionContactsPending) {
        return app.wallet.pendingContactTransactions.count;
    } else if (section == self.sectionMain) {
        NSInteger transactionCount = [data.transactions count] + app.wallet.rejectedContactTransactions.count;
#if defined(ENABLE_TRANSACTION_FILTERING) && defined(ENABLE_TRANSACTION_FETCHING)
        if (data != nil && transactionCount == 0 && !self.loadedAllTransactions && self.clickedFetchMore) {
            [app.wallet fetchMoreTransactions];
        }
#endif
        return transactionCount;
    } else {
        DLog(@"Transactions view controller error: invalid section %lu", section);
        return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)_tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == self.sectionContactsPending) {
        ContactTransaction *contactTransaction = [app.wallet.pendingContactTransactions objectAtIndex:indexPath.row];
        
        ContactTransactionTableViewCell * cell = (ContactTransactionTableViewCell *)[tableView dequeueReusableCellWithIdentifier:CELL_IDENTIFIER_CONTACT_TRANSACTION];
        
        if (cell == nil) {
            cell = [[[NSBundle mainBundle] loadNibNamed:@"ContactTransactionTableCell" owner:nil options:nil] objectAtIndex:0];
        }
        
        NSString *name = [app.wallet.contacts objectForKey:contactTransaction.contactIdentifier].name;
        [cell configureWithTransaction:contactTransaction contactName:name];
        cell.delegate = self;
        cell.selectedBackgroundView = [self selectedBackgroundViewForCell:cell];
        
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;

        return cell;
    } else if (indexPath.section == self.sectionMain) {
        
        Transaction * transaction = [self.finishedTransactions objectAtIndex:[indexPath row]];
        
        ContactTransaction *contactTransaction;
        
        if ([transaction isMemberOfClass:[ContactTransaction class]]) {
            // Declined or cancelled
            contactTransaction = (ContactTransaction *)transaction;
        } else if (transaction.myHash) {
            // Completed
            contactTransaction = [app.wallet.completedContactTransactions objectForKey:transaction.myHash];
        }
        
        if (contactTransaction) {
            ContactTransaction *newTransaction = [ContactTransaction transactionWithTransaction:contactTransaction existingTransaction:transaction];
            newTransaction.contactName = [app.wallet.contacts objectForKey:contactTransaction.contactIdentifier].name;
            
            ContactTransactionTableViewCell * cell = (ContactTransactionTableViewCell *)[tableView dequeueReusableCellWithIdentifier:CELL_IDENTIFIER_CONTACT_TRANSACTION];
            
            if (cell == nil) {
                cell = [[[NSBundle mainBundle] loadNibNamed:@"ContactTransactionTableCell" owner:nil options:nil] objectAtIndex:0];
            }
            
            NSString *name = [app.wallet.contacts objectForKey:contactTransaction.contactIdentifier].name;
            [cell configureWithTransaction:contactTransaction contactName:name];
            cell.delegate = self;

            cell.selectedBackgroundView = [self selectedBackgroundViewForCell:cell];
            
            cell.selectionStyle = contactTransaction.transactionState == ContactTransactionStateCancelled || contactTransaction.transactionState == ContactTransactionStateDeclined ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
            
            return cell;
        } else {
            TransactionTableCell * cell = (TransactionTableCell*)[tableView dequeueReusableCellWithIdentifier:@"transaction"];
            
            if (cell == nil) {
                cell = [[[NSBundle mainBundle] loadNibNamed:@"TransactionCell" owner:nil options:nil] objectAtIndex:0];
            }
            
            cell.transaction = transaction;
            
            [cell reload];
            
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;

            cell.selectedBackgroundView = [self selectedBackgroundViewForCell:cell];
            
            return cell;
        }
    } else {
        DLog(@"Invalid section %lu", indexPath.section);
        return nil;
    }
}

- (void)tableView:(UITableView *)_tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == self.sectionContactsPending) {
        
        TransactionTableCell *cell = (TransactionTableCell *)[self.tableView cellForRowAtIndexPath:indexPath];
        
        [cell transactionClicked:nil];
        
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    } else if (indexPath.section == self.sectionMain) {
        TransactionTableCell *cell = (TransactionTableCell *)[self.tableView cellForRowAtIndexPath:indexPath];
        if ([cell.transaction isMemberOfClass:[ContactTransaction class]]) {
            ContactTransaction *contactTransaction = (ContactTransaction *)cell.transaction;
            if (contactTransaction.transactionState == ContactTransactionStateCancelled ||
                contactTransaction.transactionState == ContactTransactionStateDeclined) return;
        }
        [cell transactionClicked:nil];
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    } else {
        DLog(@"Invalid section %lu", indexPath.section);
    }
}

- (void)tableView:(UITableView *)_tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
#if defined(ENABLE_TRANSACTION_FILTERING) && defined(ENABLE_TRANSACTION_FETCHING)
    if (!self.loadedAllTransactions) {
        if (indexPath.row == (int)[data.transactions count] - 1) {
            // If user scrolled down at all or if the user clicked fetch more and the table isn't filled, fetch
            if (_tableView.contentOffset.y > 0 || (_tableView.contentOffset.y <= 0 && self.clickedFetchMore)) {
                [app.wallet fetchMoreTransactions];
            } else {
                [self showMoreButton];
            }
        } else {
            [self hideMoreButton];
        }
    }
#endif
}

- (CGFloat)tableView:(UITableView *)_tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat largerCellHeight = 85;
    
    if (indexPath.section == self.sectionContactsPending) {
        return largerCellHeight;
    } else {
        Transaction *transaction = [self.finishedTransactions objectAtIndex:indexPath.row];
        return ([transaction isMemberOfClass:[ContactTransaction class]] || [app.wallet.completedContactTransactions objectForKey:transaction.myHash]) ? largerCellHeight : 65;
    }
}

- (CGFloat)tableView:(UITableView *)_tableView heightForHeaderInSection:(NSInteger)section
{
    return self.noTransactionsView.hidden ? 30 : 0;
}

- (UIView *)tableView:(UITableView *)_tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 30)];
    view.backgroundColor = COLOR_TABLE_VIEW_BACKGROUND_LIGHT_GRAY;
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(8, 8, self.view.frame.size.width, 14)];
    label.textColor = COLOR_TEXT_DARK_GRAY;
    label.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_EXTRA_SMALL];
    
    [view addSubview:label];
    
    NSString *labelString;
    
    if (section == self.sectionContactsPending) {
        labelString = BC_STRING_IN_PROGRESS;
    } else if (section == self.sectionMain) {
        labelString = BC_STRING_FINISHED;
        
    } else
        @throw @"Unknown Section";
    
    label.text = [labelString uppercaseString];
    
    return view;
}

- (void)drawRect:(CGRect)rect
{
    //Setup
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetShouldAntialias(context, YES);
    
    CGContextSetFillColorWithColor(context, [UIColor lightGrayColor].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, 320, 15));
}

- (UITableView*)tableView
{
    return tableView;
}

- (void)setText
{
    [self setupNoTransactionsView];
    
    UIColor *bounceViewBackgroundColor = [UIColor whiteColor];
    UIColor *refreshControlTintColor = [UIColor lightGrayColor];
    
    self.bounceView.backgroundColor = bounceViewBackgroundColor;
    refreshControl.tintColor = refreshControlTintColor;
    
    BOOL shouldShowFilterButton = ([app.wallet didUpgradeToHd] && ([[app.wallet activeLegacyAddresses] count] > 0 || [app.wallet getActiveAccountsCount] >= 2));
    
    filterAccountButton.hidden = !shouldShowFilterButton;
    
    // Data not loaded yet
    if (!self.data) {
        self.noTransactionsView.hidden = YES;
        
#ifdef ENABLE_TRANSACTION_FILTERING
        self.filterIndex = FILTER_INDEX_ALL;
#endif
        
        [balanceBigButton setTitle:@"" forState:UIControlStateNormal];
        [self changeFilterLabel:@""];
    }
    // Data loaded, but no transactions yet
    else if (self.data.transactions.count == 0 && app.wallet.pendingContactTransactions.count == 0 && app.wallet.rejectedContactTransactions.count == 0) {
        self.noTransactionsView.hidden = NO;
        
#if defined(ENABLE_TRANSACTION_FILTERING) && defined(ENABLE_TRANSACTION_FETCHING)
        if (!self.loadedAllTransactions) {
            [self showMoreButton];
        } else {
            [self hideMoreButton];
        }
#endif
        // Balance
        [balanceBigButton setTitle:[NSNumberFormatter formatMoney:[self getBalance] localCurrency:app->symbolLocal] forState:UIControlStateNormal];
        [self changeFilterLabel:[self getFilterLabel]];

    }
    // Data loaded and we have a balance - display the balance and transactions
    else {
        self.noTransactionsView.hidden = YES;
        
        // Balance
        [balanceBigButton setTitle:[NSNumberFormatter formatMoney:[self getBalance] localCurrency:app->symbolLocal] forState:UIControlStateNormal];
        [self changeFilterLabel:[self getFilterLabel]];
    }
}

- (void)showMoreButton
{
    self.moreButton.frame = CGRectMake(0, 0, self.view.frame.size.width, 50);
    self.moreButton.center = CGPointMake(self.view.frame.size.width/2, self.view.frame.size.height - self.moreButton.frame.size.height/2);
    self.moreButton.hidden = NO;
}

- (void)hideMoreButton
{
    self.moreButton.hidden = YES;
}

- (void)fetchMoreClicked
{
    self.clickedFetchMore = YES;
    [self reload];
}

- (void)setLatestBlock:(LatestBlock *)_latestBlock
{
    latestBlock = _latestBlock;
    
    if (latestBlock) {
        // TODO This only works if the unconfirmed transaction is included in the latest block, otherwise we would have to fetch history again to get the actual value
        // Update block index for new transactions
        for (int i = 0; i < self.data.transactions.count; i++) {
            if (((Transaction *) self.data.transactions[i]).block_height == 0) {
                ((Transaction *) self.data.transactions[i]).block_height = latestBlock.height;
            }
            else {
                break;
            }
        }
    }
}

- (void)didReceiveTransactionMessage
{
    didReceiveTransactionMessage = YES;
}

- (void)didGetMessages
{
    [self reload];
}

- (void)reload
{
    [self reloadData];
    
    [self.detailViewController didGetHistory];
}

- (void)reloadData
{
    self.sectionContactsPending = app.wallet.pendingContactTransactions.count > 0 ? 0 : -1;
    self.sectionMain = app.wallet.pendingContactTransactions.count > 0 ? 1 : 0;
    
    NSArray *rejectedTransactions = app.wallet.rejectedContactTransactions ? : @[];
    
    self.finishedTransactions = [[rejectedTransactions arrayByAddingObjectsFromArray:data.transactions] sortedArrayUsingSelector:@selector(reverseCompareLastUpdated:)];
    
    [self setText];
    
    [tableView reloadData];
    
    [self reloadNewTransactions];
    
    [self animateFirstCell];
    
    [self reloadLastNumberOfTransactions];
    
    // This should be done when request has finished but there is no callback
    if (refreshControl && refreshControl.isRefreshing) {
        [refreshControl endRefreshing];
    }
}

- (void)updateData:(MultiAddressResponse *)newData
{
    data = newData;
    
    if (app.pendingPaymentRequestTransaction) {
        Transaction *latestTransaction = [data.transactions firstObject];
        [self completeSendRequestOptimisticallyForTransaction:latestTransaction];
    }
}

- (void)reloadSymbols
{
    [self reloadData];
    
    [self.detailViewController reloadSymbols];
}

- (void)reloadNewTransactions
{
    if (data.n_transactions > lastNumberTransactions) {
        uint32_t numNewTransactions = data.n_transactions - lastNumberTransactions;
        // Max number displayed
        if (numNewTransactions > data.transactions.count) {
            numNewTransactions = (uint32_t) data.transactions.count;
        }
        // We only do this for the last five transactions at most
        if (numNewTransactions > 5) {
            numNewTransactions = 5;
        }
        
        NSMutableArray *rows = [[NSMutableArray alloc] initWithCapacity:numNewTransactions];
        for (int i = 0; i < numNewTransactions; i++) {
            [rows addObject:[NSIndexPath indexPathForRow:i inSection:self.sectionMain]];
        }
        
        [tableView reloadRowsAtIndexPaths:rows withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (void)animateFirstCell
{
    if (data.transactions.count > 0 && didReceiveTransactionMessage) {
        
        didReceiveTransactionMessage = NO;

        [self performSelector:@selector(didGetNewTransaction) withObject:nil afterDelay:0.1f];
    } else {
        hasZeroTotalBalance = [app.wallet getTotalActiveBalance] == 0;
    }
}

- (void)reloadLastNumberOfTransactions
{
    // If all the data is available, set the lastNumberTransactions - reload gets called once when wallet is loaded and once when latest block is loaded
    if (app.latestResponse) {
        lastNumberTransactions = data.n_transactions;
    }
}

- (void)loadTransactions
{
    lastNumberTransactions = data.n_transactions;

#if defined(ENABLE_TRANSACTION_FILTERING) && defined(ENABLE_TRANSACTION_FETCHING)
    if (self.loadedAllTransactions) {
        self.loadedAllTransactions = NO;
        self.clickedFetchMore = YES;
        [app.wallet getHistory];
    } else {
        BOOL tableViewIsEmpty = [self.tableView numberOfRowsInSection:self.sectionMain] == 0;
        BOOL tableViewIsFilled = ![[self.tableView indexPathsForVisibleRows] containsObject:[NSIndexPath indexPathForRow:[data.transactions count] - 1 inSection:0]];
        
        if (tableViewIsEmpty) {
            [self fetchMoreClicked];
        } else if (tableViewIsFilled) {
            self.clickedFetchMore = YES;
           [app.wallet getHistory];
        } else {
           [self fetchMoreClicked];
        }
    }
#else
    [app showBusyViewWithLoadingText:BC_STRING_LOADING_LOADING_TRANSACTIONS];
    
    [app.wallet performSelector:@selector(getHistory) withObject:nil afterDelay:0.1f];
#endif
}

- (NSDecimalNumber *)getAmountForReceivedTransaction:(Transaction *)transaction
{
    NSDecimalNumber * number = [(NSDecimalNumber*)[NSDecimalNumber numberWithLongLong:ABS(transaction.amount)] decimalNumberByDividingBy:(NSDecimalNumber*)[NSDecimalNumber numberWithLongLong:SATOSHI]];
    DLog(@"TransactionsViewController: getting amount for received transaction");
    return number;
}

- (void)didGetNewTransaction
{
    Transaction *transaction = [data.transactions firstObject];
    
    if ([transaction.txType isEqualToString:TX_TYPE_SENT]) {
        if (app.pendingPaymentRequestTransaction) {
            [app checkIfPaymentRequestFulfilled:transaction];
        } else {
            [tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:0 inSection:self.sectionMain]] withRowAnimation:UITableViewRowAnimationFade];
        };
    } else if ([transaction.txType isEqualToString:TX_TYPE_RECEIVED]) {
        
        [tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:0 inSection:self.sectionMain]] withRowAnimation:UITableViewRowAnimationFade];

        [self completeReceiveRequestOptimisticallyForTransaction:transaction];
        
        BOOL shouldShowBackupReminder = (hasZeroTotalBalance && [app.wallet getTotalActiveBalance] > 0 &&
                                         ![app.wallet isRecoveryPhraseVerified]);
        
        [app paymentReceived:[self getAmountForReceivedTransaction:transaction] showBackupReminder:shouldShowBackupReminder];
    } else {
        [tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:0 inSection:self.sectionMain]] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (void)showTransactionDetailForHash:(NSString *)hash
{
    for (Transaction *transaction in data.transactions) {
        if ([transaction.myHash isEqualToString:hash]) {
            [self showTransactionDetail:transaction];
            break;
        }
    }
}

- (void)showTransactionDetail:(Transaction *)transaction
{
    TransactionDetailViewController *detailViewController = [TransactionDetailViewController new];
    detailViewController.transactionModel = [[TransactionDetailViewModel alloc] initWithTransaction:transaction];
    
    TransactionDetailNavigationController *navigationController = [[TransactionDetailNavigationController alloc] initWithRootViewController:detailViewController];
    navigationController.transactionHash = transaction.myHash;
    
    detailViewController.busyViewDelegate = navigationController;
    navigationController.onDismiss = ^() {
        app.tabControllerManager.transactionsBitcoinViewController.detailViewController = nil;
    };
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    app.tabControllerManager.transactionsBitcoinViewController.detailViewController = detailViewController;
    
    if (app.topViewControllerDelegate) {
        [app.topViewControllerDelegate presentViewController:navigationController animated:YES completion:nil];
    } else {
        [app.tabControllerManager.tabViewController presentViewController:navigationController animated:YES completion:nil];
    }
}

- (void)changeFilterLabel:(NSString *)newText
{
    [filterAccountButton setTitle:newText forState:UIControlStateNormal];
    
    if (newText.length > 0) {
        CGFloat currentCenterY = filterAccountButton.center.y;
        [filterAccountButton sizeToFit];
        filterAccountButton.center = CGPointMake(self.view.center.x, currentCenterY);
        
        filterAccountChevronButton.frame = CGRectMake(filterAccountButton.frame.origin.x + filterAccountButton.frame.size.width, filterAccountButton.frame.origin.y, filterAccountButton.frame.size.height, filterAccountButton.frame.size.height);
    }
    
    filterAccountChevronButton.hidden = filterAccountButton.hidden;
}

- (CGFloat)heightForFilterTableView
{
    CGFloat estimatedHeight = 44 * ([app.wallet getActiveAccountsCount] + 2);
    CGFloat largestAcceptableHeight = [[UIScreen mainScreen] bounds].size.height - 150;
    return estimatedHeight > largestAcceptableHeight ? largestAcceptableHeight : estimatedHeight;
}

- (uint64_t)getBalance
{
#ifdef ENABLE_TRANSACTION_FILTERING
    if (self.filterIndex == FILTER_INDEX_ALL) {
        return [app.wallet getTotalActiveBalance];
    } else if (self.filterIndex == FILTER_INDEX_IMPORTED_ADDRESSES) {
        return [app.wallet getTotalBalanceForActiveLegacyAddresses];
    } else {
        return [app.wallet getBalanceForAccount:(int)self.filterIndex];
    }
#else
    return [app.wallet getTotalActiveBalance];
#endif
}

- (NSString *)getFilterLabel
{
#ifdef ENABLE_TRANSACTION_FILTERING
    if (self.filterIndex == FILTER_INDEX_ALL) {
        return BC_STRING_TOTAL_BALANCE;
    } else if (self.filterIndex == FILTER_INDEX_IMPORTED_ADDRESSES) {
        return BC_STRING_IMPORTED_ADDRESSES;
    } else {
        return [app.wallet getLabelForAccount:(int)self.filterIndex];
    }
#else
    return nil;
#endif
}

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller
{
    return UIModalPresentationNone;
}

- (UIView *)selectedBackgroundViewForCell:(UITableViewCell *)cell
{
    // Selected cell color
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,cell.frame.size.width,cell.frame.size.height)];
    [v setBackgroundColor:COLOR_BLOCKCHAIN_BLUE];
    return v;
}

#pragma mark - Table View Helpers

- (int)sectionCountForIndex:(int)sectionNumber
{
    return sectionNumber < 0 ? 0 : 1;
}

#pragma mark - Contacts

- (void)selectPayment:(NSString *)payment
{
    NSArray *transactions = app.wallet.pendingContactTransactions;
    NSInteger rowToSelect = -1;
    NSInteger section;
    
    for (int index = 0; index < [transactions count]; index++) {
        ContactTransaction *transaction = transactions[index];
        if ([transaction.identifier isEqualToString:payment]) {
            rowToSelect = index;
            section = self.sectionContactsPending;
            break;
        }
    }
    
    if (rowToSelect < 0) {
        transactions = self.finishedTransactions;
        
        for (int index = 0; index < [transactions count]; index++) {
            ContactTransaction *transaction = transactions[index];
            if ([transaction isMemberOfClass:[ContactTransaction class]]) {
                // Declined or cancelled
                transaction = (ContactTransaction *)transaction;
            } else if (transaction.myHash) {
                // Completed
                transaction = [app.wallet.completedContactTransactions objectForKey:transaction.myHash];
            }
            
            if ([transaction isMemberOfClass:[ContactTransaction class]] && [transaction.identifier isEqualToString:payment]) {
                rowToSelect = index;
                section = self.sectionMain;
                break;
            }
        }
    }
    
    if (rowToSelect >= 0) {
        [self tableView:self.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:rowToSelect inSection:section]];
    }

    self.messageIdentifier = nil;
}

- (void)acceptOrDeclinePayment:(ContactTransaction *)transaction forContact:(Contact *)contact
{
    NSString *message;
    NSString *reasonWithoutSpaces = [transaction.reason stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if (reasonWithoutSpaces.length > 0) {
        message = [NSString stringWithFormat:BC_STRING_ARGUMENT_WANTS_TO_SEND_YOU_ARGUMENT_FOR_ARGUMENT, contact.name, [NSNumberFormatter formatMoney:transaction.intendedAmount localCurrency:NO], transaction.reason];
    } else {
        message = [NSString stringWithFormat:BC_STRING_ARGUMENT_WANTS_TO_SEND_YOU_ARGUMENT, contact.name, [NSNumberFormatter formatMoney:transaction.intendedAmount localCurrency:NO]];
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:BC_STRING_RECEIVING_PAYMENT message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:BC_STRING_ACCEPT style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [app.wallet sendPaymentRequest:contact.identifier amount:transaction.intendedAmount requestId:transaction.identifier note:transaction.note initiatorSource:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:BC_STRING_DECLINE style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [app.wallet sendDeclination:transaction];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:BC_STRING_GO_BACK style:UIAlertActionStyleCancel handler:nil]];
    [app.tabControllerManager.tabViewController presentViewController:alert animated:YES completion:nil];
}

- (void)promptDeclinePayment:(ContactTransaction *)transaction forContact:(Contact *)contact
{
    NSString *title = transaction.reason && transaction.reason.length > 0 ? [NSString stringWithFormat:BC_STRING_DECLINE_PAYMENT_FOR_ARGUMENT, transaction.reason] : BC_STRING_DECLINE_PAYMENT;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:BC_STRING_REJECT_PAYMENT_MESSAGE preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:BC_STRING_YES_DECLINE_PAYMENT style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [app.wallet sendDeclination:transaction];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:BC_STRING_GO_BACK style:UIAlertActionStyleCancel handler:nil]];
    [app.tabControllerManager.tabViewController presentViewController:alert animated:YES completion:nil];
}

- (void)promptCancelPayment:(ContactTransaction *)transaction forContact:(Contact *)contact
{
    NSString *title = transaction.reason && transaction.reason.length > 0 ? [NSString stringWithFormat:BC_STRING_CANCEL_PAYMENT_FOR_ARGUMENT, transaction.reason] : BC_STRING_CANCEL_PAYMENT;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:BC_STRING_REJECT_PAYMENT_MESSAGE preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:BC_STRING_YES_CANCEL_PAYMENT style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [app.wallet sendCancellation:transaction];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:BC_STRING_GO_BACK style:UIAlertActionStyleCancel handler:nil]];
    [app.tabControllerManager.tabViewController presentViewController:alert animated:YES completion:nil];
}

- (void)sendPayment:(ContactTransaction *)transaction toContact:(Contact *)contact
{
    transaction.contactName = contact.name;
    
    [app setupPaymentRequest:transaction];
}

- (void)showFilterMenu
{
    BCAddressSelectionView *filterView = [[BCAddressSelectionView alloc] initWithWallet:app.wallet selectMode:SelectModeFilter];
    filterView.delegate = self;
    [app showModalWithContent:filterView closeType:ModalCloseTypeBack headerText:BC_STRING_BALANCES];
}

- (void)completeReceiveRequestOptimisticallyForTransaction:(Transaction *)transaction
{
    if (app.wallet.pendingContactTransactions.count > 0) {
        for (ContactTransaction *contactTransaction in [app.wallet.pendingContactTransactions reverseObjectEnumerator]) {
            if (contactTransaction.transactionState == ContactTransactionStateReceiveWaitingForPayment &&
                contactTransaction.intendedAmount == transaction.amount &&
                [[[transaction.to firstObject] objectForKey:DICTIONARY_KEY_ADDRESS] isEqualToString: contactTransaction.address]) {
                [app.wallet.pendingContactTransactions removeObject:contactTransaction];
                contactTransaction.transactionState = ContactTransactionStateCompletedReceive;
                [app.wallet.completedContactTransactions setObject:contactTransaction forKey:transaction.myHash];
                [self reloadData];
            }
        }
    };
}

- (void)completeSendRequestOptimisticallyForTransaction:(Transaction *)transaction
{
    if (app.wallet.pendingContactTransactions.count > 0) {
        for (ContactTransaction *contactTransaction in [app.wallet.pendingContactTransactions reverseObjectEnumerator]) {
            if (contactTransaction.transactionState == ContactTransactionStateSendReadyToSend &&
                contactTransaction.intendedAmount == llabs(transaction.amount) - llabs(transaction.fee) &&
                [[[transaction.to firstObject] objectForKey:DICTIONARY_KEY_ADDRESS] isEqualToString: contactTransaction.address]) {
                [app.wallet.pendingContactTransactions removeObject:contactTransaction];
                contactTransaction.transactionState = ContactTransactionStateCompletedSend;
                [app.wallet.completedContactTransactions setObject:contactTransaction forKey:transaction.myHash];
                [self reloadData];
            }
        }
    };
}

#pragma mark - Address Selection Delegate

- (void)didSelectFromAccount:(int)account
{
    if (account == FILTER_INDEX_IMPORTED_ADDRESSES) {
        [app filterTransactionsByImportedAddresses];
    } else {
        [app filterTransactionsByAccount:account];
    }
}

- (void)didSelectToAddress:(NSString *)address
{
    DLog(@"TransactionsViewController Warning: filtering by single imported address!")
}

- (void)didSelectToAccount:(int)account
{
    DLog(@"TransactionsViewController Warning: selected to account!")
}

- (void)didSelectFromAddress:(NSString *)address
{
    DLog(@"TransactionsViewController Warning: selected from address!")
}

- (void)didSelectContact:(Contact *)contact
{
    DLog(@"TransactionsViewController Warning: selected contact!")
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.loadedAllTransactions = NO;
    
    self.view.frame = CGRectMake(0,
                                 TAB_HEADER_HEIGHT_DEFAULT - DEFAULT_HEADER_HEIGHT,
                                 app.window.frame.size.width,
                                 app.window.frame.size.height - TAB_HEADER_HEIGHT_DEFAULT - DEFAULT_FOOTER_HEIGHT);
    
    headerView.clipsToBounds = YES;
    
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor whiteColor];
    self.tableView.scrollsToTop = YES;
    
    [balanceBigButton.titleLabel setMinimumScaleFactor:.5f];
    [balanceBigButton.titleLabel setAdjustsFontSizeToFitWidth:YES];
    
    [balanceBigButton addTarget:app action:@selector(toggleSymbol) forControlEvents:UIControlEventTouchUpInside];
    
#if defined(ENABLE_TRANSACTION_FILTERING) && defined(ENABLE_TRANSACTION_FETCHING)
    
    self.moreButton = [[UIButton alloc] initWithFrame:CGRectZero];
    [self.moreButton setTitle:BC_STRING_LOAD_MORE_TRANSACTIONS forState:UIControlStateNormal];
    self.moreButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.moreButton.backgroundColor = [UIColor whiteColor];
    [self.moreButton setTitleColor:COLOR_BLOCKCHAIN_BLUE forState:UIControlStateNormal];
    [self.view addSubview:self.moreButton];
    [self.moreButton addTarget:self action:@selector(fetchMoreClicked) forControlEvents:UIControlEventTouchUpInside];
    self.moreButton.hidden = YES;
#endif
    
    [self setupBlueBackgroundForBounceArea];
    
    [self setupPullToRefresh];
    
#ifdef ENABLE_TRANSACTION_FILTERING
    
    filterAccountButton.titleLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_SMALL_MEDIUM];
    [filterAccountButton.titleLabel setMinimumScaleFactor:1];
    [filterAccountButton.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [filterAccountButton addTarget:self action:@selector(showFilterMenu) forControlEvents:UIControlEventTouchUpInside];
    [filterAccountChevronButton addTarget:self action:@selector(showFilterMenu) forControlEvents:UIControlEventTouchUpInside];
    filterAccountChevronButton.imageView.transform = CGAffineTransformMakeScale(-1, 1);
    filterAccountChevronButton.imageEdgeInsets = UIEdgeInsetsMake(9, 4, 8, 12);

    self.filterIndex = FILTER_INDEX_ALL;
#else
    filterAccountButton.hidden = YES;
#endif
    
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    app.mainTitleLabel.hidden = YES;
    app.mainTitleLabel.adjustsFontSizeToFitWidth = YES;
    
    balanceBigButton.center = CGPointMake(headerView.center.x, balanceBigButton.center.y);
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
#ifdef ENABLE_TRANSACTION_FILTERING
    app.wallet.isFetchingTransactions = NO;
#endif
    app.mainTitleLabel.hidden = NO;
}

#pragma mark - Setup

- (void)setupBlueBackgroundForBounceArea
{
    // Blue background for bounce area
    CGRect frame = self.view.bounds;
    frame.origin.y = -frame.size.height;
    self.bounceView = [[UIView alloc] initWithFrame:frame];
    [self.tableView addSubview:self.bounceView];
    // Make sure the refresh control is in front of the blue area
    self.bounceView.layer.zPosition -= 1;
}

- (void)setupPullToRefresh
{
    // Tricky way to get the refreshController to work on a UIViewController - @see http://stackoverflow.com/a/12502450/2076094
    UITableViewController *tableViewController = [[UITableViewController alloc] init];
    tableViewController.tableView = self.tableView;
    refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self
                       action:@selector(loadTransactions)
             forControlEvents:UIControlEventValueChanged];
    tableViewController.refreshControl = refreshControl;
}

- (void)setupNoTransactionsView
{
    [self.noTransactionsView removeFromSuperview];
    
    self.noTransactionsView = [[UIView alloc] initWithFrame:CGRectMake(self.view.frame.origin.x, 0, self.view.frame.size.width, self.view.frame.size.height)];
    
    // Title label Y origin will be above midpoint between end of cards view and table view height
    UILabel *noTransactionsTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    noTransactionsTitle.textAlignment = NSTextAlignmentCenter;
    noTransactionsTitle.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_SMALL_MEDIUM];
    noTransactionsTitle.text = BC_STRING_NO_TRANSACTIONS_TITLE;
    noTransactionsTitle.textColor = COLOR_BLOCKCHAIN_BLUE;
    [noTransactionsTitle sizeToFit];
    CGFloat noTransactionsViewCenterY = (tableView.frame.size.height - self.noTransactionsView.frame.origin.y)/2 - noTransactionsTitle.frame.size.height;
    noTransactionsTitle.center = CGPointMake(self.noTransactionsView.center.x, noTransactionsViewCenterY);
    [self.noTransactionsView addSubview:noTransactionsTitle];
    self.noTransactionsTitle = noTransactionsTitle;
    
    // Description label Y origin will be 8 points under title label
    UILabel *noTransactionsDescription = [[UILabel alloc] initWithFrame:CGRectZero];
    noTransactionsDescription.textAlignment = NSTextAlignmentCenter;
    noTransactionsDescription.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_EXTRA_SMALL];
    noTransactionsDescription.numberOfLines = 0;
    noTransactionsDescription.text = BC_STRING_NO_TRANSACTIONS_TEXT;
    noTransactionsDescription.textColor = COLOR_TEXT_DARK_GRAY;
    [noTransactionsDescription sizeToFit];
    CGSize labelSize = [noTransactionsDescription sizeThatFits:CGSizeMake(170, CGFLOAT_MAX)];
    CGRect labelFrame = noTransactionsDescription.frame;
    labelFrame.size = labelSize;
    noTransactionsDescription.frame = labelFrame;
    [self.noTransactionsView addSubview:noTransactionsDescription];
    noTransactionsDescription.center = CGPointMake(self.noTransactionsView.center.x, noTransactionsDescription.center.y);
    noTransactionsDescription.frame = CGRectMake(noTransactionsDescription.frame.origin.x, noTransactionsTitle.frame.origin.y + noTransactionsTitle.frame.size.height + 8, noTransactionsDescription.frame.size.width, noTransactionsDescription.frame.size.height);
    self.noTransactionsDescription = noTransactionsDescription;
    
    // Get bitcoin button Y origin will be 16 points under description label
    self.getBitcoinButton = [[UIButton alloc] initWithFrame:CGRectMake(0, noTransactionsDescription.frame.origin.y + noTransactionsDescription.frame.size.height + 16, 130, 30)];
    self.getBitcoinButton.clipsToBounds = YES;
    self.getBitcoinButton.layer.cornerRadius = CORNER_RADIUS_BUTTON;
    self.getBitcoinButton.backgroundColor = COLOR_BLOCKCHAIN_LIGHT_BLUE;
    self.getBitcoinButton.center = CGPointMake(self.noTransactionsView.center.x, self.getBitcoinButton.center.y);
    self.getBitcoinButton.titleLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_EXTRA_SMALL];
    [self.getBitcoinButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.getBitcoinButton setTitle:[BC_STRING_GET_BITCOIN uppercaseString] forState:UIControlStateNormal];
    [self.getBitcoinButton addTarget:self action:@selector(getBitcoinButtonClicked) forControlEvents:UIControlEventTouchUpInside];
    [self.noTransactionsView addSubview:self.getBitcoinButton];
    
    [self centerNoTransactionSubviews];
    
    [tableView addSubview:self.noTransactionsView];
}

- (void)centerNoTransactionSubviews
{
    // Reposition description label Y to center of screen, and reposition title and button Y origins around it
    self.noTransactionsDescription.center = CGPointMake(self.noTransactionsTitle.center.x, self.noTransactionsView.frame.size.height/2);
    self.noTransactionsTitle.center = CGPointMake(self.noTransactionsTitle.center.x, self.noTransactionsDescription.frame.origin.y - self.noTransactionsTitle.frame.size.height - 8 + self.noTransactionsTitle.frame.size.height/2);
    self.getBitcoinButton.center = CGPointMake(self.getBitcoinButton.center.x, self.noTransactionsDescription.frame.origin.y + self.noTransactionsDescription.frame.size.height + 16 + self.noTransactionsDescription.frame.size.height/2);
    self.getBitcoinButton.hidden = NO;
}

- (void)getBitcoinButtonClicked
{
    if ([app.wallet isBuyEnabled]) {
        [app buyBitcoinClicked:nil];
    } else {
        [app.tabControllerManager receiveCoinClicked:nil];
    }
}

@end
